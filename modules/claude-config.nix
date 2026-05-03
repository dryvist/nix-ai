# Claude Code Configuration Values
#
# Centralized configuration for the programs.claude module.
# Imported by common.nix to keep it clean and high-level.
{
  config,
  pkgs,
  lib,
  ai-assistant-instructions,
  marketplaceInputs,
  claude-cookbooks,
  fabric-src,
  ...
}:

let
  # Import unified permissions from common module
  # This reads from ai-assistant-instructions agentsmd/permissions/
  # Auto mode's AI classifier handles safety for excluded categories;
  # shell.json (inline code execution) and network.json (curl mutations) are
  # excluded because auto mode detects malicious usage contextually.
  # npm run/test are false positives in the package-install deny list.
  aiCommon = import ./common {
    inherit lib config ai-assistant-instructions;
    excludeDenyFiles = [
      "shell.json"
      "network.json"
    ];
    excludeDenyCommands = [
      "npm run"
      "npm test"
    ];
  };
  inherit (aiCommon) permissions;
  inherit (aiCommon) formatters;

  # Dynamic discovery helper - finds all .md files in a directory
  discoverMarkdownFiles =
    dir:
    let
      files = if builtins.pathExists dir then builtins.readDir dir else { };
      mdFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) files;
    in
    map (name: lib.removeSuffix ".md" name) (builtins.attrNames mdFiles);

  # Discover commands and agents from configured sources
  # Commands are discovered from claude-cookbooks; agents from both ai-assistant-instructions and claude-cookbooks
  cbCommands = discoverMarkdownFiles "${claude-cookbooks}/.claude/commands";
  aiAgents = discoverMarkdownFiles "${ai-assistant-instructions}/agentsmd/agents";
  cbAgents = discoverMarkdownFiles "${claude-cookbooks}/.claude/agents";
  aiRules = discoverMarkdownFiles "${ai-assistant-instructions}/agentsmd/rules";

  # Import modular plugin configuration
  # Plugin configuration moved to claude-plugins.nix and organized by category
  # See: modules/home-manager/ai-cli/claude/plugins/*.nix
  claudePlugins = import ./claude-plugins.nix {
    inherit lib marketplaceInputs claude-cookbooks;
  };

  # Extract enabled plugins from modular configuration
  inherit (claudePlugins.pluginConfig) enabledPlugins;

  # Derive fabric version from the package (single source of truth — Renovate-managed)
  fabricVersion = (pkgs.callPackage ./fabric/package.nix { inherit fabric-src; }).version;

  # Marketplace derivation overrides (synthetic wrappers, auto-generated manifests)
  marketplaceOverrides = import ./claude/marketplace-overrides.nix {
    inherit
      pkgs
      lib
      marketplaceInputs
      fabric-src
      fabricVersion
      ;
  };
  inherit (marketplaceOverrides)
    browserUseMarketplace
    criblPackValidatorMarketplace
    jacobpevansMarketplace
    fabricMarketplace
    ;

  # Helper to build command/agent entries from discovered names
  mkSourceEntries =
    sourcePath: names:
    map (name: {
      inherit name;
      source = "${sourcePath}/${name}.md";
    }) names;

  normalizeClaudeMcpServer =
    server:
    lib.filterAttrs (
      name: value:
      lib.elem name [
        "type"
        "command"
        "args"
        "env"
        "url"
        "headers"
        "disabled"
      ]
      && value != null
      && value != [ ]
      && value != { }
      && !(name == "disabled" && !value)
    ) server;

in
{
  enable = true;

  # API Key Helper for headless authentication (cron jobs, CI/CD)
  # Uses Bitwarden Secrets Manager to securely fetch OAuth token
  # Configuration: ~/.config/bws/.env (see bws-env.example)
  apiKeyHelper = {
    enable = true;
    # scriptPath default: .local/bin/claude-api-key-helper
  };

  # teammateMode — using upstream default: "auto" (options.nix)
  # "auto" splits panes in tmux, in-process otherwise.

  # Model: opusplan — Opus for planning, Sonnet for execution (1M context).
  model = "opusplan";

  # Effort: high — maximize reasoning quality by default.
  # Must be explicit (merge script preserves runtime keys, so without this users stay on
  # whatever was last set at runtime or upstream default).
  # Override per-session via /model effort slider or "ultrathink" keyword.
  effortLevel = "high";

  # autoUpdatesChannel — using upstream default: "latest" (options.nix)
  # showTurnDuration — using upstream default: false (options.nix)

  # Enable Remote Control for all sessions (Feb 2026 feature).
  # Writes remoteControlAtStartup = true into ~/.claude.json via home.activation.
  # Allows monitoring/controlling sessions from claude.ai or the mobile app.
  # Requires a Claude Max subscription; no-op if not logged in.
  remoteControlAtStartup = true;

  # Auto-approve CLAUDE.md external imports for all repos discovered under ~/git/.
  # Generates hasClaudeMdExternalIncludesApproved = true entries in ~/.claude.json
  # for each ~/git/<repo>/main path found at home-manager activation time (runtime) via claude-json-merge.sh.
  trustedProjectDirs = [ "~/git" ];

  # Linux "Assisted-by" trailer — official AI contribution format
  # Includes LLM tool identity per Linux kernel contribution guidelines
  # Claude Code automatically appends this string to every commit message
  attribution = {
    commit = "Assisted-by: Claude <noreply@anthropic.com>";
  };

  plugins = {
    # Marketplaces from modular configuration with flakeInput for Nix symlinks
    # See: modules/home-manager/ai-cli/claude/plugins/marketplaces.nix
    # Adding flakeInput enables Nix to create immutable symlinks instead of runtime downloads
    # Standard marketplaces use raw flake input; synthetic ones override with a derivation
    marketplaces =
      let
        base = lib.mapAttrs (
          name: marketplace: marketplace // { flakeInput = marketplaceInputs.${name}; }
        ) claudePlugins.pluginConfig.marketplaces;
      in
      base
      // {
        # Override flakeInput for synthetic marketplace (source defined in marketplaces.nix)
        "browser-use-skills" = base."browser-use-skills" // {
          flakeInput = browserUseMarketplace;
        };
        # Override flakeInput for synthetic Cribl pack validator marketplace.
        "vct-cribl-pack-validator-skills" = base."vct-cribl-pack-validator-skills" // {
          flakeInput = criblPackValidatorMarketplace;
        };
        # Override flakeInput with auto-generated marketplace manifest
        "jacobpevans-cc-plugins" = base."jacobpevans-cc-plugins" // {
          flakeInput = jacobpevansMarketplace;
        };
        # Override flakeInput for synthetic fabric marketplace.
        # Wraps a curated subset of fabric patterns from data/patterns/ into
        # the .claude-plugin/ structure so they appear as skills in Claude Code.
        # Exact count is enforced by the fabric-marketplace-build check
        # (lib/checks/fabric.nix) against modules/claude/fabric-curated-patterns.json.
        "fabric-patterns" = base."fabric-patterns" // {
          flakeInput = fabricMarketplace;
        };
      };

    enabled = enabledPlugins;
    # Enable runtime plugin installation from community marketplaces.
    # Nix defines the baseline (official plugins via flake inputs).
    # Claude can dynamically install additional plugins at runtime.
    # Runtime state tracked in ~/.claude/plugins/installed_plugins.json (not Nix-managed).
    allowRuntimeInstall = true;
  };

  commands = {
    # All commands from Nix store (flake inputs) for reproducibility
    fromFlakeInputs = mkSourceEntries "${claude-cookbooks}/.claude/commands" cbCommands;
  };

  agents.fromFlakeInputs =
    (mkSourceEntries "${ai-assistant-instructions}/agentsmd/agents" aiAgents)
    ++ (mkSourceEntries "${claude-cookbooks}/.claude/agents" cbAgents);

  # Global rules (loaded every session regardless of project)
  rules.fromFlakeInputs = mkSourceEntries "${ai-assistant-instructions}/agentsmd/rules" aiRules;

  rules.local = {
    "pal-mcp-policy" = ./claude/rules/pal-mcp-policy.md;
    "retrospective-report-location" = ./claude/rules/retrospective-report-location.md;
  };

  settings = {
    # Extended thinking enabled with token budget controlled via env vars
    alwaysThinkingEnabled = true;

    # cleanupPeriodDays — using upstream default: 30 (options.nix)

    # Environment variables for model config and token optimization
    # See: https://code.claude.com/docs/en/settings
    # See: https://code.claude.com/docs/en/model-config
    env = {
      # Model: opusplan set above. Env var overrides available if needed.
      # ANTHROPIC_MODEL = "sonnet"; # Uncomment to override default model via env var
      # CLAUDE_CODE_SUBAGENT_MODEL = "claude-haiku-4-5-20251001"; # Cost control for subagents

      # Explicit model versions (Jan 2026) - pin to known working versions if customization needed
      # ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-5-20251101";
      # ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-4-5-20250929";
      # ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-haiku-4-5-20251001";

      # MCP timeout settings (5 minutes) - required for PAL MCP
      MCP_TIMEOUT = "300000";
      MCP_TOOL_TIMEOUT = "300000";

      # Experimental: Agent teams - coordinate multiple Claude Code instances
      # See: https://code.claude.com/docs/en/agent-teams
      CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";

      # Adaptive thinking for Opus/Sonnet (explicitly enabled)
      CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "0";

      # DEFAULT VALUES (upstream) - reference only, do not uncomment unless tuning
      # MAX_THINKING_TOKENS = "31999";
      # CLAUDE_CODE_MAX_OUTPUT_TOKENS = "32000";
      # BASH_MAX_OUTPUT_LENGTH = "30000";
      # MAX_MCP_OUTPUT_TOKENS = "25000";
      # SLASH_COMMAND_TOOL_CHAR_BUDGET = "16000";
      # BASH_DEFAULT_TIMEOUT_MS = "120000";  # 2 minutes
      # BASH_MAX_TIMEOUT_MS = "600000";      # 10 minutes

      # Claude.ai MCP servers (enabled by default for logged-in users)
      # ENABLE_CLAUDEAI_MCP_SERVERS = "true";

      # Plugin git operations timeout (default: 120000ms / 2 minutes)
      # CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS = "120000";

      # Effort level via env var (alternative to settings.json key)
      # CLAUDE_CODE_EFFORT_LEVEL = "medium";

      # Auto-compact threshold — using upstream default (~95% of context window)
      # CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "95";

      # ===== OpenTelemetry — OrbStack k8s OTEL Collector =====
      # Pipeline: Claude Code → OTEL Collector (:30317) → Cribl Stream (:4317) → Splunk HEC
      # Requires: OrbStack k8s running with OTEL collector deployed.
      # Source: orbstack-kubernetes/k8s/monitoring/otel-collector/service-external.yaml
      CLAUDE_CODE_ENABLE_TELEMETRY = "1";
      OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:30317";
      OTEL_EXPORTER_OTLP_PROTOCOL = "grpc";
      OTEL_METRICS_EXPORTER = "otlp";
      OTEL_LOGS_EXPORTER = "otlp";
      OTEL_TRACES_EXPORTER = "none"; # Only metrics + logs; no trace overhead
    };

    # Permissions from unified ai-assistant-instructions system
    # Uses common/permissions.nix which reads from agentsmd/permissions/
    # Formatted by common/formatters.nix to Claude Code format
    permissions = {
      allow = formatters.claude.formatAllowed permissions;
      deny = formatters.claude.formatDenied permissions;
      ask = formatters.claude.formatAsk permissions;
    };

    # Additional directories accessible to Claude Code without prompts.
    # Consumed by modules/claude/settings.nix via cfg.settings.additionalDirectories.
    # lib/claude-settings.nix (CI-only) accepts a separate caller-provided parameter.
    additionalDirectories = [
      "~/.claude/"
      "~/.claude/skills/retrospecting/reports/"
      "~/.config/direnv/"
      "~/.config/fabric/"
      "~/.config/gh/"
      "~/.config/git/"
      "~/.config/mlx/"
      "~/.config/nix/"
      "~/.config/pal-mcp/"
      "/tmp/"
    ];

    # Sandbox configuration (Dec 2025 feature)
    # Provides filesystem/network isolation when working in untrusted codebases.
    # Currently disabled - enable when reviewing external code or untrusted repos.
    sandbox = {
      enabled = false;
      # autoAllowBashIfSandboxed — using upstream default: true (options.nix)
      excludedCommands = [
        "git"
        "nix"
        "darwin-rebuild"
      ];
    };
  };

  # MCP Servers - deployed to ~/.claude.json via home.activation (see claude/settings.nix).
  # Shared definitions are owned by modules/mcp and rendered per-client here.
  mcpServers = lib.mapAttrs (_: normalizeClaudeMcpServer) config.programs.aiMcp.servers;

  statusLine = {
    enable = true;
  };

  # Hooks: Event-driven automation for Claude Code
  # See: https://code.claude.com/docs/en/hooks
  hooks = {
    # Capture last output for statusline display (Issue #479)
    # Writes compact summary of last tool execution to ~/.cache/claude-last-output.txt
    # Can be read by statusline, tmux, or other display tools
    postToolUse = ./claude/hooks/last-output.sh;

    # Refresh stale marketplace indexes after Nix rebuilds; see hooks/marketplace-refresh.sh.
    sessionStart = ./claude/hooks/marketplace-refresh.sh;

  };
}
