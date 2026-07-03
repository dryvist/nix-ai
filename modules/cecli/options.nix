#
# cecli Module — Option Declarations
#
# Mirrors the codex/gemini convention: nullableStr, enum, listOf str,
# attrsOf bool. Drop-in API surface for muscle memory from the previous
# programs.aider module — same option names where they make sense.
#
{ lib, ... }:

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
  options.programs.cecli = {
    enable = lib.mkEnableOption "cecli (maintained Aider fork) AI pair programming CLI";

    model = lib.mkOption {
      type = lib.types.str;
      default = "openai/default";
      description = ''
        Main model. Use openai/<role> names; the role is resolved by
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
      description = "Edit format for the main model. diff works well with Qwen3-Coder.";
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
      description = "Add cecli attribution to git author metadata.";
    };

    attributeCommitter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Add cecli attribution to git committer metadata.";
    };

    gitignore = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-add cecli artifact files to .gitignore.";
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
      description = "Files always added as read-only context in every session.";
    };

    hooks = {
      notification = lib.mkOption {
        type = hookType;
        default = null;
        description = "Notification hook (path or inline script). Reserved for future use.";
      };
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Free-form attrs merged into ~/.cecli.conf.yml. Keys override typed options.";
    };
  };
}
