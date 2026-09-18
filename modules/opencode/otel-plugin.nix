# OpenCode — OpenTelemetry, sharing the one telemetry surface with Claude
# Code and Codex (userConfig.telemetry).
#
# OpenCode has no native OTEL support (verified against opencode.ai/docs and
# upstream issues anomalyco/opencode#14246, #14697 — both open feature
# requests, unimplemented as of writing). The supported mechanism is the
# third-party plugin @devtheops/opencode-plugin-otel, loaded via OpenCode's
# own `plugin` config array using the documented tuple form
# `[name, options]` (README: https://github.com/DEVtheOPS/opencode-plugin-otel).
#
# Unlike Claude Code and Codex, the plugin has exactly ONE OTLP endpoint —
# metrics, logs and traces all ship to it together, so this consumer targets
# `userConfig.telemetry.otlpEndpoint` only.
{
  lib,
  userConfig,
  username,
}:
let
  telemetry = userConfig.telemetry or { };
  otlpEndpoint = telemetry.otlpEndpoint or null;
  metricsEndpoint = telemetry.metricsEndpoint or null;
  tracesEndpoint = telemetry.tracesEndpoint or null;

  # Metrics have no per-signal disable (the plugin's disabledMetrics only
  # drops individual metric suffixes, not the whole signal), so a
  # metricsEndpoint that disagrees with otlpEndpoint can't be honored or
  # safely suppressed — refuse the whole plugin rather than silently export
  # metrics to the wrong collector.
  metricsCompatible = metricsEndpoint == null || metricsEndpoint == otlpEndpoint;

  enabled = (telemetry.enable or false) && otlpEndpoint != null && metricsCompatible;

  # Same string Claude Code/Codex export, plus service.name (the plugin has
  # no dedicated serviceName option) so a shared collector attributes
  # OpenCode's signals the same way as the other two agents.
  resourceAttributes =
    (import ../../lib/telemetry-resource-attributes.nix { inherit lib userConfig username; })
    + ",service.name=${telemetry.serviceName or "opencode"}";

  # Traces DO have a whole-signal disable ("all"), so a tracesEndpoint that's
  # unset or disagrees with otlpEndpoint just turns traces off instead of
  # refusing the plugin outright. tracesEndpoint is signal-specific and
  # always carries the full /v1/traces path (maintainer-profile.nix), so it
  # is never string-equal to the base otlpEndpoint even when both target the
  # same collector -- compare against otlpEndpoint's own /v1/traces path.
  tracesMatch = tracesEndpoint != null && tracesEndpoint == "${otlpEndpoint}/v1/traces";
in
lib.optional enabled [
  "@devtheops/opencode-plugin-otel"
  {
    enabled = true;
    endpoint = otlpEndpoint;
    protocol = "http/protobuf";
    inherit resourceAttributes;
    capturePromptInLogs = telemetry.logUserPrompts or false;
    logsEnabled = true;
    disabledTraces = if tracesMatch then [ ] else [ "all" ];
  }
]
