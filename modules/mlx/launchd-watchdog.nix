#
# MLX Module — Serving Watchdog LaunchAgent
#
# Split from launchd.nix: the serving watchdog with probe discrimination and
# blast-radius scoping (see modules/mlx/scripts/mlx-watchdog.sh).
#
{
  config,
  lib,
  mlxShared,
  ...
}:
let
  inherit (mlxShared)
    cfg
    launchAgentLabel
    apiUrl
    mlxWatchdogPkg
    modelServerProcessPattern
    ;

  # Untracked, operator-seeded notification targets. nix owns the PATH; the
  # VALUE is seeded out-of-band and never committed (see mlx.cluster.alertUrlFile).
  # Defined here so the env vars below and the activation warning cannot drift.
  alertUrlFile = "${config.home.homeDirectory}/.config/mlx-cluster/alert-url";
  healthcheckUrlFile = "${config.home.homeDirectory}/.config/mlx-cluster/healthcheck-url";
in
{
  config = lib.mkIf cfg.enable {
    # Both alerters no-op silently when their url file is absent
    # (`[ -f "$file" ] || return 0`), so an unconfigured pager is
    # indistinguishable from a working one — which is how both files stayed
    # missing on both hosts across repeated rebuilds. Warn, never fail: a
    # rebuild that refused to activate because a pager is unconfigured would be
    # a worse failure than the one it reports. Named separately on purpose —
    # they are independently missing, and seeding one does not cover the other.
    home.activation.warnMlxNotificationUrls = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -s "${alertUrlFile}" ] \
        || echo "warning: mlx: ${alertUrlFile} is missing or empty — the PD-guard halt and the serving watchdog will page NOBODY. Seed a Slack incoming-webhook url (chmod 600)." 1>&2
      [ -s "${healthcheckUrlFile}" ] \
        || echo "warning: mlx: ${healthcheckUrlFile} is missing or empty — the external deadman gets no pings, so this host going silent goes unnoticed. Separate file: seeding the alert url does NOT cover this one." 1>&2
    '';

    # Serving watchdog: KeepAlive=true only restarts the proxy on process
    # EXIT, so every "up but not serving" mode is invisible to launchd — a
    # llama-swap zombie, a wedged batch scheduler answering 200 with zero
    # tokens, or a port-holding orphan making the proxy 429 everything. All
    # three keep /v1/models green, so this probes a REAL completion every
    # StartInterval. On failure it climbs an escalation ladder: reap +
    # kickstart first, then a full bootout + bootstrap once a kickstart has
    # already failed (a throttled or slot-starved unit cannot be cleared by
    # kickstart). It also reaps orphan worker trees when the uid process
    # count nears fork exhaustion, and self-gates re-fires with a cooldown
    # marker so a slow model reload is not restart-stormed (mlx-watchdog.sh).
    launchd.agents.mlx-model-server-watchdog = {
      # The probe generates against the preloaded (resident) models, so with
      # nothing preloaded every probe would cold-load a worker — worse than
      # no watchdog. Such a host has no resident serving to guard.
      #
      # NOT gated on the backend. Everything the watchdog touches is
      # backend-neutral — an OpenAI completion through llama-swap, launchctl
      # kickstart/bootout of the proxy label, and modelServerProcessPattern,
      # which already derives its own mlx-lm value. The old
      # `modelServerBackend == "vllm-mlx"` term was dead code the moment
      # assertions.nix began requiring modelServerBackend == "mlx-lm" whenever
      # the module is enabled: the two conditions cannot both hold, so the
      # agent was unconditionally disabled and no serving host had a watchdog.
      enable = cfg.preload != [ ];
      config = {
        Label = "dev.mlx-model-server.watchdog";
        ProgramArguments = [ (lib.getExe mlxWatchdogPkg) ];
        RunAtLoad = false;
        # 60 s: a zombie is detected and kickstarted within one cron gap
        # (crons fire every ~15 min), so the following tick finds it healthy.
        StartInterval = 60;
        ProcessType = "Background";
        EnvironmentVariables = {
          MLX_API_URL = apiUrl;
          MLX_LAUNCHD_LABEL = launchAgentLabel;
          MLX_MODEL_SERVER_PROCESS_PATTERN = modelServerProcessPattern;
          # Probe the whole resident set, not just the head. Each preloaded
          # model is warm by construction, so a failure means "not serving",
          # never "cold load in progress". Passing the full list lets the
          # watchdog scope its blast radius: only a brain failure restarts
          # the stack; a non-brain failure just pages.
          MLX_WATCHDOG_PROBE_MODELS_JSON = builtins.toJSON cfg.preload;
          # The brain: the one model whose failure justifies restarting the
          # whole stack. Default to the tool-calling (fleet-brain) entry when
          # it is preloaded, else the first preload entry — never a coder or
          # other non-brain, whose transient busy must not flap a healthy
          # brain (the misclassification this fix removes).
          MLX_WATCHDOG_BRAIN_MODEL =
            if lib.elem "tool-calling" cfg.preload then "tool-calling" else lib.head cfg.preload;
          # Single-model fallback for a manual/legacy run of `mlx-watchdog`
          # with no JSON list in the environment.
          MLX_WATCHDOG_PROBE_MODEL = lib.head cfg.preload;
          # Plist the rung-2 teardown re-bootstraps after `bootout` — passed
          # explicitly so the script does not guess the LaunchAgents layout.
          MLX_WATCHDOG_PLIST = "${config.home.homeDirectory}/Library/LaunchAgents/${launchAgentLabel}.plist";
          # Maps the capability alias to its physical worker so progress
          # metrics cannot be borrowed from a healthy non-brain backend.
          MLX_WATCHDOG_CONFIG = mlxShared.llamaSwapRuntimeConfigPath;
          # What a brain that stays busy past the grace window earns. The
          # ladder is only safe where a busy probe can be told apart from a
          # BUSY-BUT-PRODUCTIVE one, and the only progress signal the watchdog
          # has is vllm_mlx_engine_steps_executed on the worker's own /metrics.
          # mlx_lm.server exposes no metrics endpoint (see enableMetrics in
          # options-server.nix) and llama-swap's proxy /metrics carries host
          # gauges only — no per-model counters — so under mlx-lm the progress
          # probe fails on every tick by construction. A brain saturating its
          # concurrency slots correctly 429s each probe, which would then look
          # identical to a wedge and reap a perfectly healthy loaded model
          # every grace window. So mlx-lm pages instead of restarting; dead and
          # down (a real not-serving answer, no progress ambiguity) keep the
          # full ladder on both backends.
          MLX_WATCHDOG_BUSY_ESCALATION = if cfg.modelServerBackend == "vllm-mlx" then "restart" else "alert";
          # Untracked Slack incoming-webhook url file, shared with the cluster
          # watcher so one seeded url pages for both. Missing file = no page.
          MLX_WATCHDOG_ALERT_URL_FILE = alertUrlFile;
          # Untracked healthchecks deadman ping url file (the UUID is secret-tier,
          # so seeded out-of-band like the alert url — never committed). The
          # watchdog pings it on a healthy brain; a silent host stops pinging and
          # the external check pages. Missing file = no ping.
          MLX_WATCHDOG_HEALTHCHECK_URL_FILE = healthcheckUrlFile;
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mlx-model-server/watchdog.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mlx-model-server/watchdog.error.log";
      };
    };
  };
}
