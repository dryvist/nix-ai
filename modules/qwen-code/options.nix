#
# Qwen Code Module — Option Declarations
#
{ lib, ... }:

let
  mcpClient = import ../mcp/client.nix { inherit lib; };
in
{
  options.programs.qwen-code = {
    enable = lib.mkEnableOption "Qwen Code (Alibaba terminal coding agent)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Qwen Code package. Set from installVia; llm-agents.nix by default.
        Null skips installation, for a host that supplies the binary itself.
      '';
    };

    installVia = lib.mkOption {
      type = lib.types.enum [
        "llm-agents"
        "nixpkgs"
        "brew"
      ];
      default = "llm-agents";
      description = ''
        Install source. llm-agents.nix is the default because it tracks
        upstream closely, while nixpkgs 26.05 is frozen several minor
        versions back. Both cover every supported system, so neither ties
        this module to one platform — a brew formula did, which is what used
        to keep it macOS-only. "nixpkgs" pins the release-channel build;
        "brew" installs nothing here and relies on nix-darwin's
        homebrew.brews.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "coding";
      description = ''
        Default capability-class alias to start sessions with. Resolved
        through services.aiStack.models — `coding` maps to the
        Qwen3-Coder backend in the default registry, which is the most
        natural fit for Qwen Code's intended workload.
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Free-form attrs deep-merged into ~/.qwen/settings.json. Use to
        add additional model providers (Dashscope, OpenRouter, etc.)
        without forking the module.
      '';
    };

    contextFileNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      description = "Context file names emitted to Qwen Code settings.json; read-only.";
    };

  }
  // mcpClient.mkClientOptions "Qwen Code";
}
