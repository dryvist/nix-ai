# OpenCode OTEL plugin regression tests.
#
# Split out of opencode.nix (module option/default checks) to keep it
# focused, mirroring codex-otel.nix. OpenCode has no native OTEL support —
# the rendered plugin entry for @devtheops/opencode-plugin-otel is the whole
# surface under test here.
{ pkgs, mkHmConfigWith }:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  cfgOf = userConfigExtra: (mkHmConfigWith userConfigExtra [ ]).config.programs.opencode;

  endpoint = "https://otel.test.invalid";
  traces = "${endpoint}/v1/traces";
  metricsUrl = "${endpoint}/v1/metrics";

  noTelemetry = cfgOf { };
  noEndpoint = cfgOf { telemetry.enable = true; };
  full = cfgOf {
    telemetry = {
      enable = true;
      otlpEndpoint = endpoint;
      tracesEndpoint = traces;
    };
  };
  noTracesEndpoint = cfgOf {
    telemetry = {
      enable = true;
      otlpEndpoint = endpoint;
    };
  };
  # The plugin has one OTLP endpoint total, so a metricsEndpoint that
  # disagrees with otlpEndpoint can't be honored — the whole plugin refuses
  # rather than silently mis-routing metrics.
  metricsMismatch = cfgOf {
    telemetry = {
      enable = true;
      otlpEndpoint = endpoint;
      metricsEndpoint = metricsUrl;
    };
  };
  metricsMatch = cfgOf {
    telemetry = {
      enable = true;
      otlpEndpoint = endpoint;
      metricsEndpoint = endpoint;
    };
  };

  entryOf = cfg: builtins.elemAt cfg.otelPluginEntries 0;
  optionsOf = cfg: builtins.elemAt (entryOf cfg) 1;
in
{
  opencode-otel-wiring = helpers.mkDefaultsRegression {
    label = "OpenCode OTEL";
    checkName = "check-opencode-otel-wiring";
    checks = [
      {
        name = "no telemetry: no plugin rendered";
        actual = noTelemetry.otelPluginEntries;
        expected = [ ];
      }
      {
        name = "enable alone with no endpoint: no plugin rendered";
        actual = noEndpoint.otelPluginEntries;
        expected = [ ];
      }
      {
        name = "metrics/traces mismatch: whole plugin refused";
        actual = metricsMismatch.otelPluginEntries;
        expected = [ ];
      }
      {
        name = "full config: plugin package name";
        actual = builtins.elemAt (entryOf full) 0;
        expected = "@devtheops/opencode-plugin-otel";
      }
      {
        name = "full config: endpoint passed through verbatim";
        actual = (optionsOf full).endpoint;
        expected = endpoint;
      }
      {
        name = "full config: protocol pinned http/protobuf";
        actual = (optionsOf full).protocol;
        expected = "http/protobuf";
      }
      {
        name = "full config: matching tracesEndpoint keeps traces on";
        actual = (optionsOf full).disabledTraces;
        expected = [ ];
      }
      {
        name = "no tracesEndpoint: traces explicitly disabled, not left unset";
        actual = (optionsOf noTracesEndpoint).disabledTraces;
        expected = [ "all" ];
      }
      {
        name = "metrics endpoint matching otlpEndpoint still enables the plugin";
        actual = (builtins.length metricsMatch.otelPluginEntries) > 0;
        expected = true;
      }
      {
        name = "resource attributes carry service.name (no dedicated option in the plugin)";
        actual = (optionsOf full).resourceAttributes;
        expected = "enduser.id=test-user,service.name=opencode";
      }
    ];
  };
}
