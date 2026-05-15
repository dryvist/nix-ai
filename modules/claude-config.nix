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
  browserUseVersion,
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
      browserUseVersion
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

  autoUpdatesChannel = "stable"; # override (upstream default: "latest")
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

    cleanupPeriodDays = 180; # override (upstream default: 30)

    env = import ./claude/settings-env.nix;

    # Permissions from unified ai-assistant-instructions system
    # Uses common/permissions.nix which reads from agentsmd/permissions/
    # Formatted by common/formatters.nix to Claude Code format
    permissions = {
      allow = formatters.claude.formatAllowed permissions;
      deny = formatters.claude.formatDenied permissions;
      ask = formatters.claude.formatAsk permissions;
    };

    # Per-skill visibility overrides loaded from ai-assistant-instructions.
    # The JSON file ships as { "skillOverrides": { ... } } so we unwrap once
    # here. Tolerate a missing file so this module evaluates even when the
    # upstream input is pinned to a commit predating the JSON's introduction;
    # once the input is bumped, the overrides flow into settings.json
    # automatically.
    skillOverrides =
      let
        file = "${ai-assistant-instructions}/agentsmd/settings/skill-overrides.json";
      in
      if builtins.pathExists file then (lib.importJSON file).skillOverrides or { } else { };

    # Consumed by modules/claude/settings.nix via cfg.settings.additionalDirectories.
    # lib/claude-settings.nix (CI-only) accepts a separate caller-provided parameter.
    additionalDirectories = import ./claude/settings-paths.nix;

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
