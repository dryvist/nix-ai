# MCP Runtime — Home-Manager Module
#
# Owns all runtime infrastructure required to make the MCP server definitions
# in `./default.nix` actually executable on a user's machine:
#
#   - pal-mcp wrapper (the binary referenced by `mcp/default.nix: command = "pal-mcp"`)
#   - doppler-mcp wrapper (Doppler secret injection for any MCP server)
#   - splunk-mcp-connect helper
#   - sync-mlx-models / sync-pal-cloud-models user CLI tools
#   - palCustomModels / palCloudModels activations
#
# This module is the load-bearing piece for the MCP sub-flake's
# self-containment guarantee: importing it (alone) gives a consumer a working
# MCP runtime, with no cross-tool runtime dependencies on Claude or Codex.
#
# Decoupling from `programs.mlx`: the module reads MLX defaults via
# `lib.attrByPath` so it works whether or not the mlx home-manager module is
# also loaded. Override via `programs.mcpRuntime.pal.{mlxDefaultModel,mlxHost,mlxPort}`.
{
  config,
  lib,
  pkgs,
  pal-mcp-server,
  ...
}:

let
  cfg = config.programs.mcpRuntime;

  outputDir = "${config.home.homeDirectory}/.config/pal-mcp";
  outputFile = "${outputDir}/custom_models.json";
  palLogDir = "${config.home.homeDirectory}/.local/state/pal-mcp";

  palPkg = pkgs.callPackage ./pal-package.nix { inherit pal-mcp-server; };

  # Scripts directory holds pal-models-shared.jq, used by jq -L for `include`.
  scriptsDir = ./scripts;

  commonSyncEnv = ''
    export CURL="${pkgs.curl}/bin/curl"
    export JQ="${pkgs.jq}/bin/jq"
    export OUTPUT_DIR="${outputDir}"
    export SCRIPTS_DIR="${scriptsDir}"
  '';

  mlxSyncEnv = ''
    ${commonSyncEnv}
    export MLX_JQ_FILE="${scriptsDir}/pal-models-mlx.jq"
    export MLX_URL="http://${cfg.pal.mlxHost}:${toString cfg.pal.mlxPort}/v1/models"
    export OUTPUT_FILE="${outputFile}"
  '';

  cloudSyncEnv = ''
    ${commonSyncEnv}
    export OPENROUTER_JQ_FILE="${scriptsDir}/pal-models-openrouter.jq"
  '';
in
{
  # Namespace note: home-manager 25.11+ ships `programs.mcp` (Claude Desktop
  # MCP integration). We use `programs.mcpRuntime` to avoid the collision —
  # this module is about PAL/Doppler/Splunk MCP runtime wrappers, not the
  # upstream Claude Desktop bridge.
  options.programs.mcpRuntime = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install MCP runtime infrastructure (pal-mcp, doppler-mcp,
        sync helpers, PAL activations). Disable to opt out entirely.
      '';
    };

    pal = {
      mlxDefaultModel = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = ''
          MLX default model identifier (no `mlx-local/` prefix; the pal-mcp
          wrapper prepends that for Bifrost routing).

          Defaults to the role name "default" so pal-mcp / Bifrost route
          through services.aiStack.models, the role registry. llama-swap
          resolves "default" via its alias table to whatever physical
          mlx-community/* model the registry maps to. Override only when
          temporarily pinning pal-mcp to a specific physical model that
          should not appear in the role registry.
        '';
      };

      mlxHost = lib.mkOption {
        type = lib.types.str;
        default = lib.attrByPath [
          "programs"
          "mlx"
          "host"
        ] "127.0.0.1" config;
        defaultText = lib.literalExpression ''config.programs.mlx.host or "127.0.0.1"'';
        description = "Host where the MLX inference server listens.";
      };

      mlxPort = lib.mkOption {
        type = lib.types.port;
        default = lib.attrByPath [
          "programs"
          "mlx"
          "port"
        ] 11434 config;
        defaultText = lib.literalExpression "config.programs.mlx.port or 11434";
        description = "Port where the MLX inference server listens.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [
        # PAL MCP server — Python build from the pinned flake input.
        # Eliminates uvx git-clone + setuptools_scm permission errors.
        palPkg

        # pal-mcp — PAL launcher with baked-in env vars.
        # Env vars survive Claude Code's ~/.claude.json rewrites
        # (JacobPEvans/nix-ai#557). Dynamic paths interpolated by Nix;
        # static config in scripts/pal-mcp.sh.
        (pkgs.writeShellApplication {
          name = "pal-mcp";
          runtimeInputs = [ ]; # doppler-mcp resolved from PATH at runtime
          text = ''
            export CUSTOM_MODELS_CONFIG_PATH="${outputFile}"
            export CUSTOM_MODEL_NAME="mlx-local/${cfg.pal.mlxDefaultModel}"
            export OPENROUTER_MODELS_CONFIG_PATH="${outputDir}/openrouter_models.json"
            export PAL_LOG_DIR="${palLogDir}"
            export PAL_MCP_SERVER="${palPkg}/bin/pal-mcp-server"
          ''
          + builtins.readFile ./scripts/pal-mcp.sh;
        })

        # doppler-mcp — wraps any MCP server command with Doppler secret
        # injection. Used by mcp/default.nix `withDoppler` callers.
        # No synchronous preflight (caused 100% MCP startup failures with
        # ~17 parallel servers). See modules/mcp/README.md → Troubleshooting.
        (pkgs.writeShellApplication {
          name = "doppler-mcp";
          runtimeInputs = [ pkgs.doppler ];
          text = builtins.readFile ./scripts/doppler-mcp.sh;
        })

        # splunk-mcp-connect — Splunk MCP App stdio proxy via mcp-remote.
        # Reads SPLUNK_MCP_ENDPOINT/SPLUNK_MCP_TOKEN injected by doppler-mcp.
        (pkgs.writeShellApplication {
          name = "splunk-mcp-connect";
          runtimeInputs = [ pkgs.bun ];
          text = builtins.readFile ./scripts/splunk-mcp-connect.sh;
        })

        # sync-mlx-models — refresh custom_models.json between rebuilds.
        # Queries MLX /v1/models for available models.
        (pkgs.writeShellScriptBin "sync-mlx-models" ''
          set -euo pipefail
          ${mlxSyncEnv}
          . ${./scripts/sync-pal-models.sh}
          echo "PAL custom models updated. Restart Claude Code to pick up changes."
        '')

        # sync-pal-cloud-models — refresh OpenRouter model list between rebuilds.
        # No auth required (public API).
        (pkgs.writeShellScriptBin "sync-pal-cloud-models" ''
          set -euo pipefail
          ${cloudSyncEnv}
          . ${./scripts/sync-pal-cloud-models.sh}
          echo "PAL cloud models updated. Restart Claude Code to pick up changes."
        '')
      ];

      activation = {
        # Generate custom_models.json from dynamic MLX models.
        # Preserves previous file if the server is unreachable.
        palCustomModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${mlxSyncEnv}
          $DRY_RUN_CMD bash -c '(umask 077 && mkdir -p "${palLogDir}")'
          . ${./scripts/sync-pal-models.sh}
        '';

        # Generate cloud model configs from OpenRouter public API.
        # Skipped on dry-run (makes external network calls).
        palCloudModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${cloudSyncEnv}
          if [ -z "''${DRY_RUN_CMD:-}" ]; then
            . ${./scripts/sync-pal-cloud-models.sh}
          fi
        '';
      };
    };
  };
}
