# Telemetry wiring regression tests
#
# These pin values nix-ai itself sets, and one behaviour that is easy to
# regress silently: an OTLP endpoint has NO default, and without one nothing
# is exported at all.
#
# Both telemetry options previously defaulted to a loopback port that no
# collector has ever served. `telemetry.enable = true` therefore rendered a
# complete, plausible-looking OTLP config whose every metric and log went
# nowhere — a failure with no error message, no dropped-export warning, and no
# way to tell from the config that it was broken. The fix was to remove the
# default entirely; these checks keep it removed.
{
  pkgs,
  hmConfigTelemetryFull,
  hmConfigTelemetryNoTraces,
  hmConfigTelemetryNoEndpoint,
  hmConfigTelemetryTracesOnly,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  envOf = c: c.config.programs.claude.settings.env;

  full = envOf hmConfigTelemetryFull;
  noTraces = envOf hmConfigTelemetryNoTraces;
  noEndpoint = envOf hmConfigTelemetryNoEndpoint;
  tracesOnly = envOf hmConfigTelemetryTracesOnly;

  has = env: k: builtins.hasAttr k env;
in
{
  telemetry-otlp-wiring = helpers.mkDefaultsRegression {
    label = "Telemetry";
    checkName = "check-telemetry-otlp-wiring";
    checks = [
      # The collector speaks OTLP over HTTP protobuf. gRPC was the previous
      # value and pairs with the dead loopback port; it must not come back
      # without the endpoint changing too.
      {
        name = "metrics/logs protocol is http/protobuf";
        actual = full.OTEL_EXPORTER_OTLP_PROTOCOL;
        expected = "http/protobuf";
      }
      {
        name = "traces protocol is http/protobuf";
        actual = full.OTEL_EXPORTER_OTLP_TRACES_PROTOCOL;
        expected = "http/protobuf";
      }
      # Base URL, no /v1 suffix: the exporter appends the signal path itself.
      {
        name = "generic endpoint passed through verbatim";
        actual = full.OTEL_EXPORTER_OTLP_ENDPOINT;
        expected = "https://otel.test.invalid";
      }
      # Signal-specific, so it carries the full path.
      {
        name = "traces endpoint passed through verbatim";
        actual = full.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT;
        expected = "https://otel.test.invalid/v1/traces";
      }
      {
        name = "telemetry enabled";
        actual = full.CLAUDE_CODE_ENABLE_TELEMETRY;
        expected = "1";
      }
      # Spans need the beta flag AND a signal-specific traces endpoint. With
      # only the generic endpoint set, Claude Code emits counters and log
      # events and no span tree at all.
      {
        name = "span beta on when tracesEndpoint is set";
        actual = full.CLAUDE_CODE_ENHANCED_TELEMETRY_BETA;
        expected = "1";
      }
      {
        name = "span beta absent when tracesEndpoint is null";
        actual = has noTraces "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA";
        expected = false;
      }
      {
        name = "traces endpoint absent when tracesEndpoint is null";
        actual = has noTraces "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT";
        expected = false;
      }
      # The black-hole guard. enable alone must render NOTHING: no endpoint to
      # fall back to means no export, not an export to a guessed default.
      {
        name = "no endpoint rendered when otlpEndpoint is null";
        actual = has noEndpoint "OTEL_EXPORTER_OTLP_ENDPOINT";
        expected = false;
      }
      {
        name = "telemetry not enabled when otlpEndpoint is null";
        actual = has noEndpoint "CLAUDE_CODE_ENABLE_TELEMETRY";
        expected = false;
      }
      {
        name = "no protocol rendered when otlpEndpoint is null";
        actual = has noEndpoint "OTEL_EXPORTER_OTLP_PROTOCOL";
        expected = false;
      }
      # An OTel SDK with no endpoint falls back to a conventional loopback
      # address, so every exporter must be pinned explicitly rather than left
      # unset — otherwise "not configured" silently becomes "exporting into
      # nothing", which is the failure this whole change exists to remove.
      {
        name = "metrics exporter pinned off when otlpEndpoint is null";
        actual = noEndpoint.OTEL_METRICS_EXPORTER;
        expected = "none";
      }
      {
        name = "logs exporter pinned off when otlpEndpoint is null";
        actual = noEndpoint.OTEL_LOGS_EXPORTER;
        expected = "none";
      }
      {
        name = "traces exporter pinned off when tracesEndpoint is null";
        actual = noTraces.OTEL_TRACES_EXPORTER;
        expected = "none";
      }
      # Traces-only: each signal is gated on its OWN endpoint, so wiring spans
      # alone must not drag metrics and logs along to a pipeline that discards
      # them.
      {
        name = "traces-only still enables telemetry";
        actual = tracesOnly.CLAUDE_CODE_ENABLE_TELEMETRY;
        expected = "1";
      }
      {
        name = "traces-only exports spans";
        actual = tracesOnly.OTEL_TRACES_EXPORTER;
        expected = "otlp";
      }
      {
        name = "traces-only pins metrics off";
        actual = tracesOnly.OTEL_METRICS_EXPORTER;
        expected = "none";
      }
      {
        name = "traces-only pins logs off";
        actual = tracesOnly.OTEL_LOGS_EXPORTER;
        expected = "none";
      }
      {
        name = "traces-only sets no generic endpoint";
        actual = has tracesOnly "OTEL_EXPORTER_OTLP_ENDPOINT";
        expected = false;
      }
      {
        name = "service name identifies the emitter";
        actual = tracesOnly.OTEL_SERVICE_NAME;
        expected = "claude-code";
      }
      {
        name = "resource attributes rendered";
        actual = tracesOnly.OTEL_RESOURCE_ATTRIBUTES;
        expected = "host.name=test-host";
      }
      {
        name = "prompt content off unless explicitly enabled";
        actual = has tracesOnly "OTEL_LOG_USER_PROMPTS";
        expected = false;
      }
    ];
  };
}
