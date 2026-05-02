# Gemini Module Options
#
# Declarative options for Google Gemini CLI configuration.
# Follows the same patterns as modules/claude/options.nix.
{ lib, ... }:

let
  componentModule = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      source = lib.mkOption { type = lib.types.path; };
    };
  };

  hookType = lib.types.nullOr (lib.types.either lib.types.path lib.types.lines);

  extensionModule = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Extension description";
      };
      mcpServers = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        description = "MCP servers provided by this extension";
      };
      commands = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        description = "Commands within this extension (name -> path to .toml)";
      };
    };
  };
in
{
  options.programs.gemini = {
    enable = lib.mkEnableOption "Gemini CLI configuration";

    # Commands
    commands = {
      fromFlakeInputs = lib.mkOption {
        type = lib.types.listOf componentModule;
        default = [ ];
        description = "Command TOML files sourced from flake inputs";
      };
      local = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        description = "Local command TOML files (name -> path)";
      };
    };

    # Hooks
    hooks = {
      beforeTool = lib.mkOption {
        type = hookType;
        default = null;
        description = "Gemini BeforeTool hook";
      };
      afterTool = lib.mkOption {
        type = hookType;
        default = null;
        description = "Gemini AfterTool hook";
      };
      sessionStart = lib.mkOption {
        type = hookType;
        default = null;
        description = "Gemini SessionStart hook";
      };
      sessionEnd = lib.mkOption {
        type = hookType;
        default = null;
        description = "Gemini SessionEnd hook";
      };
      notification = lib.mkOption {
        type = hookType;
        default = null;
        description = "Gemini Notification hook";
      };
    };

    # Extensions
    extensions = lib.mkOption {
      type = lib.types.attrsOf extensionModule;
      default = { };
      description = "Nix-managed Gemini extensions";
    };

    # Trusted folders
    trustedFolders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional trusted folders (merged with defaults)";
    };

    contextFileNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      description = "Context file names emitted to Gemini settings.json; read-only.";
    };

    # Sandbox allowed paths (merged with `~/git` default so worktree operations
    # on bare repos succeed without per-host configuration).
    sandboxAllowedPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra paths the sandbox is allowed to write to.

        De-duplicated and merged with the built-in `~/git` default via
        `lib.unique`, so git operations (including worktree creation on bare
        repos) work out of the box. Duplicate entries are safe — the unique
        merge collapses them.
      '';
    };

    # Merged sandbox paths, read-only — exposes the list that ends up in
    # settings.json so regression checks and introspection can verify it.
    sandboxAllowedPathsMerged = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      description = "Merged sandbox allowed paths (default + sandboxAllowedPaths); read-only.";
    };

    # Sandbox configuration
    sandbox = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable sandbox mode for filesystem/network isolation.";
      };
      profile = lib.mkOption {
        type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
        default = null;
        description = "Path to a custom macOS sandbox profile (.sb) to use instead of the default sandbox.";
      };
    };

    # Worktrees feature
    worktrees = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable automated Git worktree management for parallel work (experimental).

        Note: gemini-cli currently writes worktrees under
        `<repo>/.gemini/worktrees/<branch>` (path is hardcoded upstream).
        Tracked at <https://github.com/google-gemini/gemini-cli> — once a
        configurable base path lands upstream, surface it here.
      '';
    };

    # Default approval mode
    defaultApprovalMode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "default"
          "auto_edit"
          "plan"
        ]
      );
      default = null;
      description = ''
        Default approval mode for tool execution.
        "auto_edit" auto-approves file edits without prompting.
        Null omits the key from settings.json (Gemini uses its built-in default).
      '';
    };

    # MCP servers to exclude from shared definitions
    excludedMcpServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cloudflare"
        "cribl"
        "docker"
        "everything"
        "exa"
        "fetch"
        "filesystem"
        "firecrawl"
        "git"
        "github"
        "terraform"
      ];
      description = "MCP servers to exclude from the shared definitions";
    };
  };
}
