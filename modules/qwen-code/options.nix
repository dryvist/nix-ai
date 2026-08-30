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
        Qwen Code package. Defaults to pkgs.qwen-code (nixpkgs).
        Null skips installation, for a host that supplies the binary itself.
      '';
    };

    installVia = lib.mkOption {
      type = lib.types.enum [
        "nixpkgs"
        "brew"
      ];
      default = "nixpkgs";
      description = ''
        Install source. nixpkgs ships qwen-code as of 26.05, so the brew
        formula is no longer needed and no longer the default — that
        dependency is what kept this module macOS-only. "brew" is retained
        for a host that deliberately wants the bottled build; it installs
        nothing here, relying on nix-darwin's homebrew.brews.
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
