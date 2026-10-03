# Codex OTEL metrics/trace exporter regression tests.
#
# Split out of telemetry.nix (Claude's own OTEL suite) to stay under the
# repo's file-size gate. Codex's unset metrics_exporter defaults to its
# built-in Statsig exporter, not "nothing" (codex-rs/config/src/types.rs:
# OtelConfig::default().metrics_exporter is OtelExporterKind::Statsig), so
# both exporters must always render explicitly — these checks pin that.
{ pkgs, mkHmConfigWith }:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  configOf = userConfigExtra: (mkHmConfigWith userConfigExtra [ ]).config;

  endpoint = "https://otel.test.invalid";
  traces = "${endpoint}/v1/traces";
  metricsUrl = "${endpoint}/v1/metrics";

  noTelemetry = configOf { };
  logsOnly = configOf {
    telemetry = {
      enable = true;
      otlpEndpoint = "${endpoint}/";
    };
  };
  metricsOnly = configOf {
    telemetry = {
      enable = true;
      metricsEndpoint = metricsUrl;
    };
  };
  tracesOnly = configOf {
    telemetry = {
      enable = true;
      tracesEndpoint = traces;
    };
  };
  bothTelemetry = {
    enable = true;
    tracesEndpoint = traces;
    metricsEndpoint = metricsUrl;
  };
  both = configOf { telemetry = bothTelemetry; };
  # Claude Code's own env, same telemetry config, for the cross-agent parity
  # check below.
  claudeBoth = (configOf { telemetry = bothTelemetry; }).programs.claude.settings.env;
in
{
  codex-otel-logs-rendered =
    pkgs.runCommand "check-codex-otel-logs-rendered"
      {
        activation = logsOnly.home.activation.codexConfigMerge.data;
        passAsFile = [ "activation" ];
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        toml=$(grep -m1 -oE '/nix/store/[^"[:space:]]*codex-config\.toml' "$activationPath")
        python3 - "$toml" <<'PY'
        import sys, tomllib
        with open(sys.argv[1], "rb") as source:
            otel = tomllib.load(source)["otel"]
        assert otel["exporter"] == {"otlp-http": {"endpoint": "https://otel.test.invalid/v1/logs", "protocol": "binary"}}
        assert otel["metrics_exporter"] == "none"
        assert otel["trace_exporter"] == "none"
        assert otel["log_user_prompt"] is False
        PY
        touch "$out"
      '';

  codex-otel-wiring = helpers.mkDefaultsRegression {
    label = "Codex OTEL";
    checkName = "check-codex-otel-wiring";
    checks = [
      {
        name = "no telemetry: both exporters pinned none";
        actual = noTelemetry.programs.codex.otelExporterKinds;
        expected = {
          logs = "none";
          trace = "none";
          metrics = "none";
        };
      }
      {
        name = "no telemetry: no OTEL_RESOURCE_ATTRIBUTES leaked";
        actual = noTelemetry.home.sessionVariables ? OTEL_RESOURCE_ATTRIBUTES;
        expected = false;
      }
      {
        name = "metrics-only: metrics otlp-http, trace stays none";
        actual = metricsOnly.programs.codex.otelExporterKinds;
        expected = {
          logs = "none";
          trace = "none";
          metrics = "otlp-http";
        };
      }
      {
        name = "traces-only: trace otlp-http, metrics stays none";
        actual = tracesOnly.programs.codex.otelExporterKinds;
        expected = {
          logs = "none";
          trace = "otlp-http";
          metrics = "none";
        };
      }
      {
        name = "both signals: both exporters otlp-http";
        actual = both.programs.codex.otelExporterKinds;
        expected = {
          logs = "none";
          trace = "otlp-http";
          metrics = "otlp-http";
        };
      }
      {
        name = "logs-only: logs otlp-http, other signals stay none";
        actual = logsOnly.programs.codex.otelExporterKinds;
        expected = {
          logs = "otlp-http";
          trace = "none";
          metrics = "none";
        };
      }
      {
        # One identity across every OTel-aware agent a user runs.
        name = "OTEL_RESOURCE_ATTRIBUTES matches Claude Code's env value";
        actual = both.home.sessionVariables.OTEL_RESOURCE_ATTRIBUTES;
        expected = claudeBoth.OTEL_RESOURCE_ATTRIBUTES;
      }
    ];
  };
}
