# OpenCode Module Options
{ lib, ... }:
let
  mcpClient = import ../mcp/client.nix { inherit lib; };
in
{
  options.programs.opencode = {
    enable = lib.mkEnableOption "OpenCode (sst/opencode terminal agent)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        OpenCode package. Defaults to pkgs.opencode (nixpkgs).
        Null skips installation, for a host that supplies the binary itself.
      '';
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = ".config/opencode";
      description = ''
        Directory (relative to $HOME) holding `opencode.json` and `command/`.
        Also the path the agent-skills registry symlinks skills and AGENTS.md
        into, so a consumer relocates the config dir here once.
      '';
    };

    commandDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Directories whose *.md files are linked into the opencode command directory (~/.config/opencode/command/ by default).";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Attrs merged into the opencode config (~/.config/opencode/opencode.json; wins over module defaults).";
    };

    extraModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Physical model IDs or router aliases exposed alongside the router
        capability aliases (`modules/litellm-local/aliases.nix`) under the
        LiteLLM provider in OpenCode. Empty by default: the alias list
        already covers every selectable tier. A committed list here would
        duplicate the router's own registry and drift from it — read the
        live menu (`GET /v1/models` on the router) for a physical id instead
        of hardcoding one.
      '';
    };

    litellmRoles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      description = "Router capability aliases rendered into OpenCode's provider.litellm and agent tiers; read-only, sourced from modules/litellm-local/aliases.nix.";
    };

    lspEnabled = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      internal = true;
      description = "Whether LSP integration is enabled in the rendered opencode.json; introspection for the regression checks, mirroring mcpServerNames.";
    };

    otelPluginEntries = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      readOnly = true;
      internal = true;
      description = ''
        Raw @devtheops/opencode-plugin-otel `plugin` tuple entries rendered
        from `userConfig.telemetry` (see otel-plugin.nix); empty when
        telemetry is off or has no usable endpoint. Introspection for the
        regression checks, mirroring codex's otelExporterKinds.
      '';
    };
  }
  // mcpClient.mkClientOptions "OpenCode";
}
