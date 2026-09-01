# The two launchd agents the local proxy owns.
#
# Split out of ./default.nix to stay under the .file-size.yml ceiling and to
# follow the per-module launchd.nix pattern already used by fabric and mlx.
#
# They are deliberately SEPARATE agents. The proxy is KeepAlive and serves live
# traffic; the refresh is a short interval job that reaches two network
# endpoints, one of which has been measured hanging intermittently. Folding the
# refresh into the proxy would let a failed catalog fetch restart something that
# was serving fine.
#
# Neither agent may carry a credential in `EnvironmentVariables`: launchd
# agents get no shell init, so each reads the router bearer from its file at
# exec time instead. `lib/checks/litellm-local.nix` asserts the proxy agent
# carries no `OPENAI_API_KEY`.
{
  config,
  lib,
  cfg,
  aiStack,
  proxyScript,
  fallbackWatch,
  telemetryTracesEndpoint,
}:
let
  logDir = "${config.home.homeDirectory}/Library/Logs/litellm-local";
  # Same operator-seeded pager the mlx watchdog uses. Deliberately the SAME
  # file: a host with a pager configured should not have to seed a second one
  # to learn that its fallback chain died.
  alertUrlFile = "${config.home.homeDirectory}/.config/mlx-cluster/alert-url";
in
{
  litellm-local = {
    enable = true;
    config = {
      Label = "dev.litellm-local";
      ProgramArguments = [ "${proxyScript}" ];
      RunAtLoad = true;
      KeepAlive = true;
      # Throttle restarts so a bad config or an unreadable secret file fails
      # visibly in the log instead of spinning.
      #
      # 10, not 30, and the difference is a live-session outage. Claude Code on
      # this host reaches Anthropic THROUGH this proxy, so every restart is a
      # hard outage for every session on the machine — and `darwin-rebuild`
      # rewrites this plist, so any converge that touches this module bounces
      # it. launchd will not restart a job sooner than ThrottleInterval after
      # it stopped, so 30 turned a measured 3.2s startup into an outage of up
      # to ~33s: long enough to outrun a client's retry budget and drop the
      # session. Measured 2026-08-28 — readiness from cold start to a serving
      # /v1/models is 3.2s, so 10s still leaves a crash loop slow enough to
      # read in the log while cutting the worst case to ~13s.
      ThrottleInterval = 10;
      ProcessType = "Background";
      EnvironmentVariables = {
        # Not a secret — the router URL is a plain address, so it needs no
        # exec-time file read. Same for the loopback endpoint this host's own
        # models are served on.
        LLM_ROUTER_URL = aiStack.llmRouterEndpoint;
        LOCAL_LLM_URL = cfg.localEndpoint;
        HOME = config.home.homeDirectory;
      }
      # LiteLLM reads its OWN names here — `OTEL_EXPORTER` / `OTEL_ENDPOINT`
      # — not the standard OTEL_EXPORTER_OTLP_* pair. Setting the standard
      # names instead leaves the callback pointed at its loopback default
      # and exporting nowhere, with no error. Endpoint carries the full
      # signal path because LiteLLM posts it verbatim.
      // lib.optionalAttrs (telemetryTracesEndpoint != null) {
        OTEL_EXPORTER = "otlp_http";
        OTEL_ENDPOINT = telemetryTracesEndpoint;
      };
      StandardOutPath = "${logDir}/litellm-local.log";
      StandardErrorPath = "${logDir}/litellm-local.error.log";
    };
  };

  # ALERT ON ABSENCE OF SUCCESS. KeepAlive above restarts the proxy only when
  # the process EXITS, so every "up but not serving" mode is invisible to
  # launchd — and a fallback rung that 404s every request keeps the proxy
  # perfectly healthy. Config inspection cannot see it either: a rung's params
  # can render exactly right and still name a group the upstream does not
  # serve.
  #
  # So this sends a REAL completion to every rung on an interval and pages when
  # one stops answering. Its own agent, not folded into the proxy: this reaches
  # the network and must never be able to restart something that was serving
  # fine.
  litellm-fallback-watch = {
    enable = true;
    config = {
      Label = "dev.litellm-fallback-watch";
      ProgramArguments = [ "${fallbackWatch}/bin/litellm-fallback-watch" ];
      # Not RunAtLoad: a converge bounces the proxy, and probing it mid-restart
      # would page on the restart rather than on a dead rung.
      RunAtLoad = false;
      StartInterval = 900;
      ProcessType = "Background";
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        LITELLM_LOCAL_URL = "http://127.0.0.1:${toString cfg.port}";
        LITELLM_ALERT_URL_FILE = alertUrlFile;
      };
      StandardOutPath = "${logDir}/fallback-watch.log";
      StandardErrorPath = "${logDir}/fallback-watch.error.log";
    };
  };
}
