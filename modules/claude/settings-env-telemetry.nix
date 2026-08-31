# Claude Code — OpenTelemetry environment, split out of settings-env.nix.
#
# A function of { lib, userConfig } returning only the OTEL key/value pairs.
# Lives in its own file because settings-env.nix sits against the repo's
# file-size gate, and this block is the largest cohesive piece in it.
#
# Opt-in via userConfig.telemetry (maintainer profile). Off by default so a
# fresh consumer emits no telemetry.
#
# The endpoints are INDEPENDENT, and each signal is exported only when its own
# endpoint is set. None carries a default. That is the whole point: an OTel SDK
# given no endpoint falls back to a conventional loopback address, so "leave it
# unset" is not the same as "do not export" — it silently exports to somewhere
# nothing is listening. Every exporter is therefore pinned to an explicit
# `otlp` or `none` below, never left to the SDK's default. A collector address
# is site-specific; a wrong-but-plausible one is indistinguishable from working
# telemetry at every layer, which is why no default is offered here.
#
# Splitting the signals also matters downstream: a collector may accept and
# acknowledge all three while its pipeline extracts only one, so pointing a
# signal at a collector that discards it reproduces the same silent loss one
# layer further away.
{ lib, userConfig }:
{ }
# Master switch: on when telemetry is enabled AND at least one signal has
# somewhere to go. Without it Claude Code emits nothing, whatever the exporters
# and endpoints below say.
//
  lib.optionalAttrs
    (
      (userConfig.telemetry.enable or false)
      && (
        (userConfig.telemetry.otlpEndpoint or null) != null
        || (userConfig.telemetry.metricsEndpoint or null) != null
        || (userConfig.telemetry.tracesEndpoint or null) != null
      )
    )
    (
      {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_SERVICE_NAME = userConfig.telemetry.serviceName or "claude-code";
      }
      // lib.optionalAttrs (userConfig.telemetry.logUserPrompts or false) {
        OTEL_LOG_USER_PROMPTS = "1";
      }
      // lib.optionalAttrs (userConfig.telemetry.logToolDetails or false) {
        OTEL_LOG_TOOL_DETAILS = "1";
      }
      // lib.optionalAttrs ((userConfig.telemetry.resourceAttributes or { }) != { }) {
        OTEL_RESOURCE_ATTRIBUTES = lib.concatStringsSep "," (
          lib.mapAttrsToList (k: v: "${k}=${v}") userConfig.telemetry.resourceAttributes
        );
      }
    )

# Logs, and metrics when they share the generic endpoint. That endpoint is a
# BASE url — the exporter appends /v1/metrics and /v1/logs itself.
//
  lib.optionalAttrs
    ((userConfig.telemetry.enable or false) && (userConfig.telemetry.otlpEndpoint or null) != null)
    {
      OTEL_EXPORTER_OTLP_ENDPOINT = userConfig.telemetry.otlpEndpoint;
      OTEL_LOGS_EXPORTER = "otlp";
    }

# Metrics ride the generic endpoint unless a signal-specific one is set. A
# metrics-only sink is common — a Prometheus-family TSDB accepts OTLP metrics
# and has no logs route at all — and pointing the generic endpoint at one turns
# on a logs exporter that fails every interval. metricsEndpoint carries the
# full /v1/metrics path and wins when both are set.
//
  lib.optionalAttrs
    (
      (userConfig.telemetry.enable or false)
      && (
        (userConfig.telemetry.metricsEndpoint or null) != null
        || (userConfig.telemetry.otlpEndpoint or null) != null
      )
    )
    (
      {
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        OTEL_METRICS_EXPORTER = "otlp";
        # Prometheus-family sinks (VictoriaMetrics, Mimir, Prometheus) silently
        # drop delta-temporality metrics — the pipeline looks healthy while
        # storing nothing. Cumulative is what they expect and is accepted by
        # every OTLP collector, so it is safe to pin unconditionally.
        OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "cumulative";
        # The SDK's 60s default loses the final interval of short sessions —
        # a sub-minute CLI run can exit having exported nothing. 10s bounds
        # that loss without meaningful overhead at this metric volume.
        OTEL_METRIC_EXPORT_INTERVAL = "10000";
      }
      // lib.optionalAttrs ((userConfig.telemetry.metricsEndpoint or null) != null) {
        OTEL_EXPORTER_OTLP_METRICS_ENDPOINT = userConfig.telemetry.metricsEndpoint;
      }
    )

# ...and each signal is explicitly off when it has no endpoint, so the SDK
# cannot fall back to its conventional loopback default and export into
# nothing.
// lib.optionalAttrs (
  (userConfig.telemetry.enable or false)
  && (userConfig.telemetry.metricsEndpoint or null) == null
  && (userConfig.telemetry.otlpEndpoint or null) == null
) { OTEL_METRICS_EXPORTER = "none"; }
// lib.optionalAttrs (
  (userConfig.telemetry.enable or false) && (userConfig.telemetry.otlpEndpoint or null) == null
) { OTEL_LOGS_EXPORTER = "none"; }

# Trace spans → a signal-specific endpoint carrying the full /v1/traces path;
# nothing is appended to it. Setting it also turns on the enhanced-telemetry
# beta, which is the flag that makes Claude Code emit the
# interaction/llm_request/tool/tool.execution/subagent span tree at all. With
# only the generic endpoint set, the CLI emits zero trace traffic.
//
  lib.optionalAttrs
    ((userConfig.telemetry.enable or false) && (userConfig.telemetry.tracesEndpoint or null) != null)
    {
      CLAUDE_CODE_ENHANCED_TELEMETRY_BETA = "1";
      OTEL_TRACES_EXPORTER = "otlp";
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = userConfig.telemetry.tracesEndpoint;
      OTEL_EXPORTER_OTLP_TRACES_PROTOCOL = "http/protobuf";
    }

# ...and explicitly off otherwise, for the same reason as metrics and logs.
//
  lib.optionalAttrs
    ((userConfig.telemetry.enable or false) && (userConfig.telemetry.tracesEndpoint or null) == null)
    {
      OTEL_TRACES_EXPORTER = "none";
    }
