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
      default = "nixpkgs";
      description = ''
        Install source. nixpkgs is the default because it is the only one of
        the three with a cache hit on every consumer. llm-agents.nix carries a
        much newer qwen-code (0.23.0 against 26.05's 0.16.0) and is selectable
        for a host that wants it, but it is NOT the default: nix-darwin has no
        numtide substituter, so choosing it there builds qwen-code from source,
        and that build exhausts the JS heap on a CI runner (`tsc --build`,
        "Ineffective mark-compacts near heap limit"). qwen-code does not need
        to track upstream closely enough to justify that.

        Neither Nix source ties this module to one platform — a brew formula
        did, which is what used to keep it macOS-only. "brew" installs nothing
        here and relies on nix-darwin's homebrew.brews.
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
