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
      default = [
        "deepseek/deepseek-v4.1-flash"
        "deepseek-flash"
        "qwen/qwen-max"
        "qwen-max"
        "qwen3.8-max"
        "z-ai/glm-5.3-flash"
        "minimax/minimax-m3"
        "mlx-community/Qwen3.8-27B-4bit"
        "mlx-community/Qwen3.6-35B-A3B-4bit"
        "mlx-community/Qwen3.5-9B-MLX-4bit"
      ];
      description = ''
        Physical model IDs and rolling aliases exposed alongside role aliases
        under the LiteLLM provider in OpenCode.
      '';
    };
  }
  // mcpClient.mkClientOptions "OpenCode";
}
