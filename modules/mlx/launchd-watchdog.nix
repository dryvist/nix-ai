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
    ;
in
{
  config = lib.mkIf cfg.enable {
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
    launchd.agents.vllm-mlx-watchdog = {
      # The probe generates against the preloaded (resident) models, so with
      # nothing preloaded every probe would cold-load a worker — worse than
      # no watchdog. Such a host has no resident serving to guard.
      enable = cfg.preload != [ ];
      config = {
        Label = "dev.vllm-mlx.watchdog";
        ProgramArguments = [ (lib.getExe mlxWatchdogPkg) ];
        RunAtLoad = false;
        # 60 s: a zombie is detected and kickstarted within one cron gap
        # (crons fire every ~15 min), so the following tick finds it healthy.
        StartInterval = 60;
        ProcessType = "Background";
        EnvironmentVariables = {
          MLX_API_URL = apiUrl;
          MLX_LAUNCHD_LABEL = launchAgentLabel;
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
          # Untracked ntfy url file, shared with the cluster watcher so one
          # seeded url pages for both. Missing file = no page.
          MLX_WATCHDOG_ALERT_URL_FILE = "${config.home.homeDirectory}/.config/mlx-cluster/alert-url";
          # Untracked healthchecks deadman ping url file (the UUID is secret-tier,
          # so seeded out-of-band like the alert url — never committed). The
          # watchdog pings it on a healthy brain; a silent host stops pinging and
          # the external check pages. Missing file = no ping.
          MLX_WATCHDOG_HEALTHCHECK_URL_FILE = "${config.home.homeDirectory}/.config/mlx-cluster/healthcheck-url";
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-watchdog.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/vllm-mlx/vllm-mlx-watchdog.error.log";
      };
    };
  };
}
