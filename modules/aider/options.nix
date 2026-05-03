#
# Aider Module — Option Declarations
#
# programs.aider.* options mirror the codex/gemini convention:
# nullableStr, enum, listOf str, attrsOf bool.
#
{ pkgs, lib, ... }:

let
  hookType = lib.types.nullOr (lib.types.either lib.types.path lib.types.lines);
  editFormatType = lib.types.nullOr (
    lib.types.enum [
      "whole"
      "diff"
      "udiff"
      "architect"
      "editor-diff"
      "editor-whole"
    ]
  );
in
{
  options.programs.aider = {
    enable = lib.mkEnableOption "Aider AI pair programming CLI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.aider-chat-full;
      defaultText = lib.literalExpression "pkgs.aider-chat-full";
      description = ''
        Aider package. Set to null when useUvx = true.
        Override to pkgs.aider-chat for the base package without extras.
      '';
    };

    useUvx = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, install a writeShellScriptBin "aider" wrapper that runs
        `uv tool run --from "aider-chat" aider` instead of the nixpkgs package.
        Gives access to the latest upstream release at the cost of reproducibility.
        Set package = null when enabling this.
      '';
    };

    routing = lib.mkOption {
      type = lib.types.enum [
        "llama-swap"
        "bifrost"
      ];
      default = "llama-swap";
      description = ''
        Inference routing target.
        - llama-swap: Direct to http://127.0.0.1:11434/v1 (local MLX, default).
          Model names are openai/<role>; llama-swap resolves via useModelName.
        - bifrost: Through http://localhost:30080/v1 (multi-provider gateway).
          Model names gain the mlx-local/ prefix for local MLX routing.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "openai/default";
      description = ''
        Main Aider model. Use openai/<role> names; the role is resolved by
        llama-swap to the physical HF id (see services.aiStack.models).
      '';
    };

    weakModel = lib.mkOption {
      type = lib.types.str;
      default = "openai/quickest";
      description = "Cheap-task model used for commit messages and summaries.";
    };

    editorModel = lib.mkOption {
      type = lib.types.str;
      default = "openai/coding";
      description = "Editor model used in architect/editor-pair mode.";
    };

    editFormat = lib.mkOption {
      type = editFormatType;
      default = "diff";
      description = "Aider edit format for the main model. diff works well with Qwen3-Coder.";
    };

    weakEditFormat = lib.mkOption {
      type = editFormatType;
      default = "whole";
      description = "Edit format for the weak model. whole is safest for smaller models.";
    };

    autoCommits = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-commit after each successful edit.";
    };

    dirtyCommits = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow commits when the working tree has uncommitted changes.";
    };

    attributeAuthor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Add Aider attribution to git author metadata.";
    };

    attributeCommitter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Add Aider attribution to git committer metadata.";
    };

    gitignore = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-add Aider artifact files to .gitignore.";
    };

    lint = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run linter after each edit (uses the project's default linter).";
    };

    autoTest = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run tests after each edit. Off by default — too aggressive for large suites.";
    };

    pretty = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Color and format terminal output.";
    };

    stream = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Stream model responses to the terminal.";
    };

    darkMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use dark color theme.";
    };

    readFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "CLAUDE.md"
        "AGENTS.md"
        "GEMINI.md"
      ];
      description = "Files always added as read-only context in every Aider session.";
    };

    hooks = {
      notification = lib.mkOption {
        type = hookType;
        default = null;
        description = "Aider notification hook (path or inline script). Reserved for future use.";
      };
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Free-form attrs merged into ~/.aider.conf.yml. Keys override typed options.";
    };
  };
}
