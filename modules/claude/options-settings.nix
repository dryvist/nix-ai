# Claude Code Module — `settings.json` option declarations
#
# Everything that lands inside the deployed `settings.json`: thinking mode,
# session cleanup, skill-listing budget, permissions, accessible directories,
# environment variables, schema URL, and sandbox configuration.
{ lib, ... }:
{
  options.programs.claude.settings = {
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

    # Skill listing budget
    skillListingBudgetFraction = lib.mkOption {
      type = lib.types.float;
      default = 0.02;
      description = ''
        Fraction of the context window reserved for skill descriptions in
        every session. Claude Code's upstream default is 0.01 (1%), which
        drops descriptions when many plugins are enabled.

        Default 0.02 (2%) doubles the upstream allocation — enough headroom
        for the universal plugin set without dropping descriptions. Raise
        further only if /doctor still reports "skill descriptions dropped".
      '';
    };

    # Per-skill visibility overrides
    skillOverrides = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.enum [
          "on"
          "name-only"
          "user-invocable-only"
          "off"
        ]
      );
      default = { };
      example = {
        "django-pro" = "off";
        "saga-orchestration" = "name-only";
      };
      description = ''
        Per-skill visibility overrides written to ~/.claude/settings.json
        for personal, project, and managed skills (not plugin skills — those
        are controlled via /plugin). Keys are bare skill names. Values:
          on                    — full description + /menu entry (default)
          name-only             — name listed; description dropped from context
          user-invocable-only   — hidden from Claude; only / invocation works
          off                   — hidden everywhere; removed from context entirely

        Loaded from agentsmd/settings/skill-overrides.json in
        claude-config.nix; safe to leave empty.
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

    # Auto-mode classifier configuration. Lands at top-level `autoMode`
    # in settings.json (NOT under permissions). See
    # https://code.claude.com/docs/en/auto-mode-config.
    #
    # Setting defaultMode = "auto" enables the classifier; this block
    # configures what it trusts. Out of the box the classifier trusts
    # only the working directory and the active repo's remotes, so
    # populating `environment` is the single highest-leverage tuning
    # action — it stops the classifier from blocking routine cross-repo,
    # cross-org, cloud, and homelab operations.
    autoMode = {
      environment = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "$defaults" ];
        description = ''
          Trusted infrastructure entries. Prose strings, read as
          natural-language rules. Include `"$defaults"` to inherit the
          built-in entries (working repo plus configured remotes) and
          splice your entries before/after. Omit `"$defaults"` to
          replace the entire built-in list — rarely desired.
        '';
      };
      allow = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "$defaults" ];
        description = ''
          Exceptions to `soft_deny` rules. Prose strings. Include
          `"$defaults"` to inherit built-ins.
        '';
      };
      soft_deny = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "$defaults" ];
        description = ''
          Destructive actions blocked unless overridden by explicit user
          intent or an `allow` entry. Include `"$defaults"` to inherit
          the built-in soft-block list (force-push, `curl | bash`,
          production deploys, etc.).
        '';
      };
      hard_deny = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "$defaults" ];
        description = ''
          Unconditional blocks. Include `"$defaults"` to inherit the
          built-in list (data exfiltration patterns, auto-mode bypass
          attempts, etc.).
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
}
