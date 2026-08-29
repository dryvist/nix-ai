# Executables the local proxy ships: the launchd entry point and the two
# operator commands.
#
# Split out of ./default.nix to stay under the .file-size.yml ceiling. Grouped
# by responsibility rather than by size — everything here produces something
# runnable, while ./proxy-config.nix decides what the proxy serves and
# default.nix wires the module.
#
# Common thread worth keeping in view: none of these may take a credential
# through the Nix store or through a launchd `EnvironmentVariables` entry. The
# router bearer is read from its file at exec time, every time.
{
  pkgs,
  lib,
  aiStack,
  cfg,
  versions,
  configYaml,
  fallbackTier,
  telemetryTracesEndpoint,
  otelPackages,
}:
let
  # The proxy runs from a uvx environment pinned to the Renovate-tracked release
  # in lib/versions.nix, the same way the MLX stack does, rather than from
  # nixpkgs' litellm: nixpkgs lags the upstream release train by months, and
  # building it from source drags a large Python test closure (the rq test
  # suite among it) into every CI and workstation rebuild.
  uvPythonVersion = (import ../../lib/python.nix { inherit pkgs; }).pythonVersion;

  # Liveness probe for the fallback chain. The chain's members are named here
  # so the command needs no arguments in the common case — running it bare
  # checks exactly what this host is configured to fall back through.
  fallbackProbe = pkgs.writeShellApplication {
    name = "litellm-fallback-probe";
    runtimeInputs = [
      pkgs.curl
      pkgs.python3
    ];
    # The chain is passed as an environment variable, not as default
    # arguments: `"''${@:-a b c}"` collapses the default into ONE argument, so
    # the probe asked for a model literally named "a b c" and got a 404 that
    # looked like a dead chain. Word-splitting the default belongs in the
    # script, which is also where the no-inline-shell rule wants it.
    text = ''
      LITELLM_FALLBACK_CHAIN=${lib.escapeShellArg (lib.concatStringsSep " " fallbackTier.names)} \
        exec ${./../scripts/litellm-fallback-probe.sh} "$@"
    '';
  };

  # Regenerates ./tier-candidates.json from the live catalog. It writes into a
  # CHECKOUT, not the store, so the candidates path is a required argument
  # rather than baked in — a wrapper pointing at the read-only store copy would
  # fail at the last step, after both network fetches.
  tierRefresh = pkgs.writeShellApplication {
    name = "litellm-tier-refresh";
    runtimeInputs = [
      pkgs.curl
      pkgs.python3
    ];
    text = ''
      exec ${./../scripts/litellm-tier-refresh.sh} "$@"
    '';
  };

  # launchd agents get no shell init, so the wrapper reads the router bearer
  # from its file itself. This is also why the assertion below requires
  # llmEndpointTokenFile: llmEndpointBearerFromEnv provisions the bearer into
  # an interactive shell, which this agent never has.
  proxyScript = pkgs.writeShellScript "litellm-local-start" ''
    set -euo pipefail
    OPENAI_API_KEY="$(cat ${lib.escapeShellArg (toString aiStack.llmEndpointTokenFile)})"
    export OPENAI_API_KEY
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} \
      --from "litellm[proxy]==${versions.litellm}" \
      ${
        lib.concatMapStringsSep " " (p: "--with ${lib.escapeShellArg p}") (
          lib.optionals (telemetryTracesEndpoint != null) otelPackages
        )
      } litellm \
      --config ${configYaml} \
      --host 127.0.0.1 \
      --port ${toString cfg.port}
  '';
in
{
  inherit fallbackProbe tierRefresh proxyScript;
}
