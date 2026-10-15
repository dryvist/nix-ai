#
# Qwen Code Module — Option Declarations
#
{
  lib,
  pkgs,
  config,
  ...
}:

let
  modelMode = import ./model-mode.nix { inherit config lib; };
  usesRouterCapabilities =
    config.programs.litellmLocal.enable || config.services.aiStack.llmEndpoint == "router";
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

    sandbox.enable = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isDarwin";
      description = ''
        Launch Qwen Code through the deny-default Seatbelt profile with an
        allowlisted environment. The profile is applied by
        /usr/bin/sandbox-exec, so this is macOS only. When false, `qwen` runs
        the package directly.
      '';
    };

    sandbox.workRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/qwen-code-work";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/qwen-code-work"'';
      description = ''
        Directory holding the standalone clones Qwen Code may open in the
        sandbox; linked worktrees and checkouts elsewhere are refused. The
        profile denies writes to project configuration and git metadata.
      '';
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = if modelMode.bySize then modelMode.modelNames else [ ];
      description = ''
        MLX catalog keys Qwen Code may select in by-size mode. Each entry must
        name a Qwen model in the catalog and be statically resident on this
        host. Router-only hosts use their existing capability aliases.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default =
        if modelMode.bySize then
          modelMode.defaultModel
        else if usesRouterCapabilities then
          "medium"
        else
          "coding";
      description = ''
        Default model for Qwen Code. Hosts with a static Qwen resident use its
        catalog key; other hosts use their existing local role or router alias.
      '';
    };

    excludeTools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "skill"
        "todo_write"
        "agent"
        "ask_user_question"
      ];
      description = ''
        Built-in tools to deny to reduce the first-session prompt size when
        using a local model. Entries are bare tool names rendered into
        `permissions.deny`; set to `[ ]` to re-enable all built-in tools.
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

    generatedSettings = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "Rendered Qwen Code settings before writing settings.json.";
    };

    sandboxLocalPorts = lib.mkOption {
      type = lib.types.listOf lib.types.ints.positive;
      readOnly = true;
      internal = true;
      description = "Loopback ports passed to the Qwen Code sandbox profile.";
    };

  }
  // mcpClient.mkClientOptions "Qwen Code";
}
