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

  # The probe, on a schedule, paging when a rung stops answering. The probe
  # itself was already "the only check that settles it" (fallback-tier.nix) and
  # nothing ran it, so a converged host could carry a correct config and a rung
  # that 404s every request with the machine having no opinion about it.
  fallbackWatch = pkgs.writeShellApplication {
    name = "litellm-fallback-watch";
    runtimeInputs = [
      pkgs.curl
      pkgs.python3
      pkgs.coreutils
    ];
    text = ''
      LITELLM_PROBE_BIN=${fallbackProbe}/bin/litellm-fallback-probe \
        exec ${./../scripts/litellm-fallback-watch.sh} "$@"
    '';
  };

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
  inherit
    fallbackProbe
    fallbackWatch
    proxyScript
    ;
}
