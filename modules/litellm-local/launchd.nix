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
  telemetryTracesEndpoint,
  tierRefreshJob,
  tierRefreshScript,
  refreshCandidates,
}:
let
  refreshCfg = cfg.tierRefresh;
  logDir = "${config.home.homeDirectory}/Library/Logs/litellm-local";
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
        # exec-time file read.
        LLM_ROUTER_URL = aiStack.llmRouterEndpoint;
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

  # Periodic re-ranking. Separate agent from the proxy on purpose: the
  # proxy is KeepAlive and must never restart because a refresh failed,
  # and the refresh is a short interval job that must be allowed to fail
  # without taking traffic with it.
  litellm-tier-refresh = lib.mkIf refreshCfg.enable {
    enable = true;
    config = {
      Label = "dev.litellm-tier-refresh";
      ProgramArguments = [
        "${lib.getExe tierRefreshJob}"
        refreshCandidates
        "${tierRefreshScript}"
      ];
      StartInterval = refreshCfg.interval;
      # Not at load: a rebuild already re-reads the file it would rewrite,
      # so firing on every login adds two network round trips and no
      # information.
      RunAtLoad = false;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        # Both are non-secret — an address and a PATH. The bearer itself is
        # read from that file at exec time by the refresh script, never
        # placed in a launchd environment, matching the proxy agent and the
        # assertion in lib/checks/litellm-local.nix.
        LLM_ROUTER_URL = aiStack.llmRouterEndpoint;
        LLM_ROUTER_TOKEN_FILE = toString aiStack.llmEndpointTokenFile;
      };
      StandardOutPath = "${logDir}/tier-refresh.log";
      StandardErrorPath = "${logDir}/tier-refresh.error.log";
    };
  };
}
