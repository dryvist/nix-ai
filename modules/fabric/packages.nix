#
# Fabric Module — Package, Patterns, Environment
#
# Exposes the fabric CLI binary, symlinks the 252+ pattern library from the
# fabric-src flake input, and sets session variables.
#
{
  config,
  lib,
  fabric-src,
  fabricShared,
  ...
}:
let
  inherit (fabricShared) cfg fabricPkg;
  inherit (config.services.aiStack) resolvedLlmEndpoint llmEndpoint;

  # Single source of truth for the patterns symlink location. The relative
  # path (patternsKey) is used as the home.file attribute key; the absolute
  # path (patternsDir) is exported via FABRIC_PATTERNS_DIR. They are always
  # in sync because both derive from the same constant.
  patternsKey = ".config/fabric/patterns";
  patternsDir = "${config.home.homeDirectory}/${patternsKey}";
in
{
  config = lib.mkIf cfg.enable {
    # The `home.*` attribute set groups the fabric CLI binary, pattern symlinks,
    # session variables, and custom patterns directory activation into a single
    # merged key. Example CLI usage:
    #   echo "content" | fabric --pattern summarize
    #   fabric -y "https://youtube.com/watch?v=..." --pattern extract_wisdom
    #   git diff | fabric --pattern create_git_diff_commit
    #
    # Patterns are symlinked read-only from the fabric-src flake input to
    # ~/.config/fabric/patterns/. Each pattern directory contains system.md
    # (AI instructions) and user.md (human documentation).
    #
    # Session variables point fabric at the local MLX stack by default; users
    # can override per-invocation with --model or --url flags.
    #
    # When customPatternsDir is set (default ~/.config/fabric/custom-patterns)
    # the directory is created on activation and FABRIC_CUSTOM_PATTERNS_DIR is
    # exported so users can drop their own patterns alongside the read-only ones.
    home = {
      packages = [ fabricPkg ];

      file.${patternsKey} = {
        source = "${fabric-src}/data/patterns";
      };

      sessionVariables = {
        FABRIC_PATTERNS_DIR = patternsDir;
        FABRIC_DEFAULT_MODEL = cfg.defaultModel;
      }
      // lib.optionalAttrs (cfg.customPatternsDir != null) {
        FABRIC_CUSTOM_PATTERNS_DIR = cfg.customPatternsDir;
      }
      # Point fabric at the router when services.aiStack.llmEndpoint = "router".
      # LIMITATION: fabric's endpoint/keys canonically live in the user-managed
      # ~/.config/fabric/.env (via `fabric --setup`), which Nix does not own, so
      # this cannot be a per-tool setting — OPENAI_BASE_URL is a home-wide
      # sessionVariable. It is exported only in router mode (local mode leaves
      # fabric on its .env value, unchanged); godotenv does not override an
      # already-set env var, so this shell export wins over any OPENAI_BASE_URL
      # in .env, but vendor selection and API keys in .env stay authoritative.
      // lib.optionalAttrs (llmEndpoint != "mlx_local") {
        OPENAI_BASE_URL = resolvedLlmEndpoint;
      };

      activation = lib.optionalAttrs (cfg.customPatternsDir != null) {
        fabricCustomPatternsDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD mkdir -p ${cfg.customPatternsDir}
        '';
      };
    };
  };
}
