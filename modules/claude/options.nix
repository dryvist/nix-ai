# Claude Code Module Options
#
# All configuration options for the unified Claude Code module.
# Cross-platform: no Darwin-specific code here.
{ lib, ... }:

let
  # Reusable submodule types
  marketplaceModule = lib.types.submodule {
    options = {
      source = lib.mkOption {
        type = lib.types.submodule {
          options = {
            type = lib.mkOption {
              type = lib.types.enum [
                "git"
                "github"
                "local"
              ];
              default = "git";
            };
            url = lib.mkOption { type = lib.types.str; };
          };
        };
      };
      flakeInput = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Flake input for Nix-managed (immutable) plugins";
      };
      overlayFiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        description = "Files to overlay onto the marketplace (dest path relative to marketplace root → source file)";
      };
    };
  };

  componentModule = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      source = lib.mkOption { type = lib.types.path; };
    };
  };

  mcpServerModule = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [
          "stdio"
          "sse"
          "http"
        ];
        default = "stdio";
      };
      command = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
      };
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      headers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
      };
      disabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };

  hookType = lib.types.nullOr (lib.types.either lib.types.path lib.types.lines);

in
{
  options.programs.claude = {
    enable = lib.mkEnableOption "Claude Code configuration";

    # Plugins
    plugins = {
      marketplaces = lib.mkOption {
        type = lib.types.attrsOf marketplaceModule;
        default = { };
      };
      enabled = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = { };
      };
      allowRuntimeInstall = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };

    # Commands
    commands = {
      fromFlakeInputs = lib.mkOption {
        type = lib.types.listOf componentModule;
        default = [ ];
      };
      local = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
      };
      fromLiveRepo = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };
      liveRepoCommands = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

    # Agents
    agents = {
      fromFlakeInputs = lib.mkOption {
        type = lib.types.listOf componentModule;
        default = [ ];
      };
      local = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
      };
    };

    # Skills
    skills = {
      fromFlakeInputs = lib.mkOption {
        type = lib.types.listOf componentModule;
        default = [ ];
      };
      local = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
      };
    };

    # Rules (global user rules, loaded every session regardless of project)
    rules = {
      fromFlakeInputs = lib.mkOption {
        type = lib.types.listOf componentModule;
        default = [ ];
      };
      local = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
      };
    };

    # Hooks - fully implemented in modules/claude/settings.nix
    # Generates executable scripts in ~/.claude/hooks/ via home.file.
    hooks = {
      preToolUse = lib.mkOption {
        type = hookType;
        default = null;
      };
      postToolUse = lib.mkOption {
        type = hookType;
        default = null;
      };
      userPromptSubmit = lib.mkOption {
        type = hookType;
        default = null;
      };
      stop = lib.mkOption {
        type = hookType;
        default = null;
      };
      subagentStop = lib.mkOption {
        type = hookType;
        default = null;
      };
      sessionStart = lib.mkOption {
        type = hookType;
        default = null;
      };
      sessionEnd = lib.mkOption {
        type = hookType;
        default = null;
      };
    };

    # MCP Servers
    mcpServers = lib.mkOption {
      type = lib.types.attrsOf mcpServerModule;
      default = { };
    };

    # API Key Helper (for headless authentication)
    # Requires ~/.config/bws/.env with Bitwarden/Claude API key env vars.
    # bws_helper.py performs minimal validation — see it for required vars.
    apiKeyHelper = {
      enable = lib.mkEnableOption "API key helper for headless Claude authentication";

      scriptPath = lib.mkOption {
        type = lib.types.str;
        default = ".local/bin/claude-api-key-helper";
        description = "Path (relative to home) where the API key helper script is installed";
      };
    };

    # Agent teams: coordinate multiple Claude Code instances
    # See: https://code.claude.com/docs/en/agent-teams
    teammateMode = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "in-process"
        "tmux"
      ];
      default = "auto";
      description = ''
        Display mode for agent team teammates.
        - "auto": split panes if already in tmux, in-process otherwise
        - "in-process": all teammates in main terminal (Shift+Up/Down to navigate)
        - "tmux": force split-pane mode (requires tmux)
      '';
    };

    # Auto-update channel for Claude Code binary
    autoUpdatesChannel = lib.mkOption {
      type = lib.types.enum [
        "stable"
        "latest"
      ];
      default = "latest";
      description = ''
        Release channel for Claude Code binary updates.
        - "latest": newest releases immediately (default upstream)
        - "stable": ~1 week delay, fewer regressions
      '';
    };

    # Show turn duration in UI
    showTurnDuration = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show how long each turn takes in the Claude Code UI";
    };

    # Remote Control auto-start (Feb 2026 feature)
    # Stored in ~/.claude.json (global config) via home.activation.
    # See: https://code.claude.com/docs/en/remote-control
    remoteControlAtStartup = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = ''
        Enable Remote Control for all sessions automatically.
        null = leave unmanaged (Claude Code default is false).
      '';
    };

    # Trusted project directories for CLAUDE.md external import approval.
    # Stored in ~/.claude.json under projects.<path> at activation time.
    trustedProjectDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Base directories containing git repos (worktree layout).
        At activation time, discovers all subdirectories and generates
        trust entries (hasClaudeMdExternalIncludesApproved, hasTrustDialogAccepted)
        for each "$baseDir/$repo/main" path in ~/.claude.json.
      '';
      example = [ "~/git" ];
    };

    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Override the default model. Accepts aliases ("opus", "sonnet",
        "haiku", "opusplan") or full names ("claude-opus-4-7").
        null = account-tier default. See: https://code.claude.com/docs/en/model-config
      '';
    };

    effortLevel = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "low"
          "medium"
          "high"
        ]
      );
      default = null;
      description = ''
        Adaptive reasoning effort for Opus and Sonnet.
        - null: Use upstream default (medium for Max/Team as of v2.1.68)
        - "high": Full reasoning
        - "medium": Balanced cost/quality
        - "low": Minimal reasoning, fastest and cheapest
        Override per-session via /model effort slider or "ultrathink" keyword.
      '';
    };

    attribution = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Commit attribution trailer appended to every commit message. Default uses Linux kernel-style Assisted-by trailer format.";
    };

    # Runtime data cleanup — prunes stale session artifacts on home-manager switch
    runtimeCleanup = {
      enable = lib.mkEnableOption "Prune stale ~/.claude runtime data on home-manager switch";
      retentionDays = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Delete runtime data (projects, todos, snapshots, etc.) older than this many days";
      };
      maxBackups = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Maximum number of ~/.claude.json backups to retain";
      };
    };

    # Settings
    settings = {
      # Extended thinking mode
      alwaysThinkingEnabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable Claude's extended thinking capability by default.
          When enabled, Claude can reason through complex problems step-by-step.
          Token budget controlled by MAX_THINKING_TOKENS in env.
        '';
      };

      # Session management
      cleanupPeriodDays = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = ''
          Sessions inactive longer than this period are deleted.
          Upstream Claude default is 30 days.
        '';
      };

      # Permissions
      permissions = {
        allow = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Commands and operations to auto-approve without prompting";
        };
        deny = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Commands and operations to permanently block";
        };
        ask = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Commands and operations requiring user confirmation";
        };
        defaultMode = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "acceptEdits"
              "auto"
              "bypassPermissions"
              "default"
              "dontAsk"
              "plan"
            ]
          );
          default = "auto";
          description = ''
            Default permission mode for Claude Code sessions.
            - "auto": AI classifier decides per-action (eliminates most prompts)
            - "default": prompt for everything (upstream default)
            - "acceptEdits": auto-approve file edits, prompt for shell
            - "bypassPermissions": bypass all permission checks (sandboxes only)
            - "dontAsk": bypass all prompts (use with caution)
            - "plan": plan mode by default
            - null: omit from settings.json (use upstream default)
          '';
        };
      };

      additionalDirectories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Directories accessible to Claude Code without prompts";
        example = [
          "~/projects"
          "~/Documents"
          "~/.config"
        ];
      };

      # Environment variables for Claude Code
      # See: https://code.claude.com/docs/en/settings
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Environment variables passed to Claude Code.
          See: https://code.claude.com/docs/en/settings
        '';
        example = {
          MAX_THINKING_TOKENS = "16000";
          CLAUDE_CODE_MAX_OUTPUT_TOKENS = "16000";
        };
      };

      schemaUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://json.schemastore.org/claude-code-settings.json";
        description = "JSON schema URL for settings validation";
      };

      # Sandbox configuration (Dec 2025 feature)
      # Provides filesystem/network isolation for untrusted codebases
      sandbox = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable sandbox mode for filesystem/network isolation.
            Useful when working in untrusted codebases.
          '';
        };
        autoAllowBashIfSandboxed = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Automatically allow bash commands when sandboxed.
            Safe because sandbox prevents destructive operations.
          '';
        };
        excludedCommands = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Commands to exclude from sandbox restrictions";
          example = [
            "git"
            "nix"
            "darwin-rebuild"
          ];
        };
      };
    };

    # Status Line (supports claude-code-statusline)
    statusLine = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      script = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
      };
    };

    # Feature Flags
    features = {
      pluginSchemaVersion = lib.mkOption {
        type = lib.types.int;
        default = 1;
      };
      experimental = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = { };
      };
    };
  };
}
