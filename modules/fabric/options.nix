#
# Fabric Module — Option Declarations
#
# All `options.programs.fabric` declarations live here.
#
{ config, lib, ... }:
{
  options.programs.fabric = {
    enable = lib.mkEnableOption "Daniel Miessler's Fabric AI prompt pattern framework";

    enableServer = lib.mkEnableOption "Fabric REST API server as a macOS LaunchAgent";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address for the fabric REST API server";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8180;
      description = ''
        Port for the fabric REST API server.

        Default 8180 avoids conflicts with:
        - 11434: llama-swap proxy (MLX stack)
        - 11436: vllm-mlx backend
        - 27124: Obsidian Local REST API
      '';
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = ''
        Default model fabric should use when no `--model` flag is specified.

        Defaults to the role name "default" so fabric, llama-swap, and the
        rest of the AI stack share a single source of truth in
        services.aiStack.models. Routes through the local MLX stack at
        http://127.0.0.1:11434/v1.

        Override to a cloud provider model id (any Claude, Gemini, or GPT model
        your provider exposes) but be aware fabric needs API keys
        configured in ~/.config/fabric/.env for those backends.
      '';
    };

    # patternsDir is intentionally NOT configurable — it is a computed constant
    # that always matches the home.file symlink location in packages.nix. Making
    # it user-overridable would let the FABRIC_PATTERNS_DIR env var diverge from
    # the actual filesystem location. Custom patterns belong in customPatternsDir.

    customPatternsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${config.home.homeDirectory}/.config/fabric/custom-patterns";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.config/fabric/custom-patterns"'';
      description = ''
        User-managed directory for custom fabric patterns alongside the
        Nix-managed read-only patterns at programs.fabric.patternsDir.

        Set to null to disable custom pattern support entirely. When set,
        the directory is created on activation and FABRIC_CUSTOM_PATTERNS_DIR
        is exported into the user shell so fabric discovers patterns dropped
        here without writing to the read-only Nix store.

        Pattern directory layout matches upstream fabric:
          <customPatternsDir>/
            my_pattern_name/
              system.md   # required
              user.md     # optional, ignored by fabric

        Discoverable via `fabric -l | grep my_pattern_name`.
      '';
    };
  };
}
