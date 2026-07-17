# Antigravity Module Options
#
# Declarative options for Google Antigravity CLI configuration.
# Follows the same per-agent option patterns as the other agent modules
# (see docs/architecture/per-agent-flakes.md).
{ lib, ... }:

let
  mcpClient = import ../mcp/client.nix { inherit lib; };

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
  options.programs.antigravity-cli = {
    enable = lib.mkEnableOption "Antigravity CLI configuration";

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
        description = "Antigravity BeforeTool hook";
      };
      afterTool = lib.mkOption {
        type = hookType;
        default = null;
        description = "Antigravity AfterTool hook";
      };
      sessionStart = lib.mkOption {
        type = hookType;
        default = null;
        description = "Antigravity SessionStart hook";
      };
      sessionEnd = lib.mkOption {
        type = hookType;
        default = null;
        description = "Antigravity SessionEnd hook";
      };
      notification = lib.mkOption {
        type = hookType;
        default = null;
        description = "Antigravity Notification hook";
      };
    };

    # Extensions
    extensions = lib.mkOption {
      type = lib.types.attrsOf extensionModule;
      default = { };
      description = "Nix-managed Antigravity extensions";
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
      description = "Context file names emitted to Antigravity settings.json; read-only.";
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
        `<repo>/.gemini/antigravity-cli/worktrees/<branch>` (path is hardcoded upstream).
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
        Null omits the key from settings.json (Antigravity uses its built-in default).
      '';
    };

    # Default chat model
    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Pin Antigravity CLI's default chat model (sets model.name in settings.json).
        Accepts any value the upstream CLI accepts: tier aliases ("pro", "flash",
        "flash-lite"), "auto" family aliases, or explicit model IDs from the
        upstream registry. Prefer aliases over versioned IDs so this option
        does not go stale when upstream ships new models.
        See the in-CLI /model dialog or upstream settings.schema.json for
        the current accepted values.
        null leaves Antigravity CLI's own model resolution alone.
        NOTE: Google-hosted model values execute in Google's cloud. To
        route generation elsewhere, point GOOGLE_GEMINI_BASE_URL at any
        self-hosted Gemini-compatible endpoint.
      '';
    };

    # Experimental local Gemma classifier router (LiteRT-LM)
    gemmaModelRouter = {
      enable = lib.mkEnableOption "experimental local Gemma classifier router (LiteRT-LM)";

      autoStartServer = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Automatically start the LiteRT-LM server when Antigravity CLI starts.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9379;
        description = "Local port for the LiteRT-LM classifier HTTP server.";
      };

      classifierModel = lib.mkOption {
        type = lib.types.str;
        default = "gemma3-1b-gpu-custom";
        description = ''
          LiteRT-LM bundle name used by the local classifier. This is a
          LiteRT-LM identifier, NOT an MLX model ID — different runtime,
          different catalog. Discover available bundles via the runtime's
          list-models subcommand. Cannot reference services.aiStack.models
          (those are MLX models served by a different stack).
        '';
      };

      binaryPath = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Override path to the LiteRT-LM binary. Empty string uses Antigravity CLI's default (~/.gemini/antigravity-cli/bin/litert/).";
      };
    };

    # excludedMcpServers + mcpServerNames come from the shared MCP client helper.
  }
  // mcpClient.mkClientOptions "Antigravity CLI";
}
