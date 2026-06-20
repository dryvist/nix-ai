# Claude Code Configuration Values
#
# User-facing values for the programs.claude module. The option schema and
# settings.json renderer now live in `nix-claude-code` (imported via
# `nix-claude-code.homeModules.claude` in flake/home-manager-modules.nix);
# this module just assigns user-specific values to the schema.
#
# Marketplaces, synthetic marketplace derivations, and the marketplace
# catalog are sourced from `nix-claude-code.lib.{marketplaceCatalog,
# marketplaceOverrides}` so the canonical list stays in one repo.
{
  config,
  pkgs,
  lib,
  ai-assistant-instructions,
  nix-claude-code,
  marketplaceInputs,
  claude-cookbooks,
  fabric-src,
  userConfig ? {
    user.fullName = "JacobPEvans";
  },
  ...
}:

let
  # Permission engine still lives in nix-ai's `modules/common` because it's
  # also consumed by Codex/Gemini formatters. The raw permission data
  # (allow/ask/deny/domains) now comes from `nix-claude-code.lib.permissions`
  # (Checkpoint 3, step 2; data true-up verified in dryvist/nix-claude-code#50);
  # only the formatter API stays local.
  aiCommon = import ./common {
    inherit lib config nix-claude-code;
    excludeDenyCategories = [
      "shell"
      "network"
    ];
    excludeDenyCommands = [
      "npm run"
      "npm test"
    ];
  };
  inherit (aiCommon) permissions;
  inherit (aiCommon) formatters;

  # Dynamic discovery helper — finds all .md files in a directory
  discoverMarkdownFiles =
    dir:
    let
      files = if builtins.pathExists dir then builtins.readDir dir else { };
      mdFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) files;
    in
    map (name: lib.removeSuffix ".md" name) (builtins.attrNames mdFiles);

  cbCommands = discoverMarkdownFiles "${claude-cookbooks}/.claude/commands";
  aiAgents = discoverMarkdownFiles "${ai-assistant-instructions}/agentsmd/agents";
  cbAgents = discoverMarkdownFiles "${claude-cookbooks}/.claude/agents";
  aiRules = discoverMarkdownFiles "${ai-assistant-instructions}/agentsmd/rules";

  # Plugin tier files (per-user enablement) stay in nix-ai. The catalog of
  # marketplaces themselves now lives in nix-claude-code.
  pluginTiers = import ./claude/plugins {
    inherit lib marketplaceInputs;
  };

  inherit (pluginTiers) enabledPlugins;

  # Derive versions from packages and lib (single source of truth for Renovate)
  fabricVersion = (pkgs.callPackage ./fabric/package.nix { inherit fabric-src; }).version;
  browserUseVersion = (import ../lib/versions.nix).browserUse;

  # Marketplace catalog and synthetic-marketplace derivations come from
  # nix-claude-code. Catalog defines names + source URLs; overrides build
  # the four synthetic derivations (browser-use, cribl, jacobpevans, fabric).
  inherit (nix-claude-code.lib) marketplaceCatalog;
  marketplaceOverrides = nix-claude-code.lib.marketplaceOverrides {
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
  programs.claude = {
    enable = true;

    # Binary comes from Homebrew (claude-code@latest cask in nix-darwin);
    # Nix manages config only. Claude's native updater (latest channel)
    # overlays the newest build at ~/.local/bin/claude on top of the brew
    # baseline. See nix-claude-code core.nix: package = null skips home.packages.
    package = null;

    # API Key Helper for headless authentication (cron jobs, CI/CD)
    # Uses Bitwarden Secrets Manager to securely fetch OAuth token
    # Configuration: ~/.config/bws/.env (see bws-env.example)
    apiKeyHelper = {
      enable = true;
      # scriptPath default: .local/bin/claude-api-key-helper
    };

    # Model: opusplan — Opus for planning, Sonnet for execution (1M context).
    model = "opusplan";

    # Effort intentionally left unset: nix-claude-code defaults `effortLevel`
    # to null, which Claude Code reads as the upstream default. Override
    # per-session via /effort.

    # Enable Remote Control for all sessions (Feb 2026 feature).
    remoteControlAtStartup = true;

    # Auto-approve CLAUDE.md external imports for all repos discovered under ~/git/public/.
    trustedProjectDirs = [ "~/git/public/" ];

    # Commit trailer per https://docs.kernel.org/process/coding-assistants.html.
    attribution = {
      commit = "Assisted-by: Claude:{model}";
    };

    plugins = {
      # Marketplace catalog comes from nix-claude-code; we overlay each entry
      # with the resolved flakeInput (synthetic for the four wrapper
      # derivations; raw marketplace input otherwise).
      marketplaces =
        let
          base = lib.mapAttrs (
            name: marketplace:
            marketplace
            // {
              flakeInput = marketplaceInputs.${name} or null;
            }
          ) (marketplaceCatalog.marketplaces or marketplaceCatalog);
        in
        base
        // {
          "browser-use-skills" = (base."browser-use-skills" or { }) // {
            flakeInput = browserUseMarketplace;
          };
          "vct-cribl-pack-validator-skills" = (base."vct-cribl-pack-validator-skills" or { }) // {
            flakeInput = criblPackValidatorMarketplace;
          };
          # jacobpevans-cc-plugins isn't in nix-claude-code's catalog yet;
          # register it directly with the synthetic wrapper derivation.
          "jacobpevans-cc-plugins" = {
            source = {
              type = "github";
              url = "JacobPEvans/claude-code-plugins";
            };
            flakeInput = jacobpevansMarketplace;
          };
          "fabric-patterns" = {
            source = {
              type = "github";
              url = "danielmiessler/fabric";
            };
            flakeInput = fabricMarketplace;
          };
          # karpathy-skills lives in nix-ai (input + tier file).
          # nix-claude-code's catalog doesn't include it.
          "karpathy-skills" = {
            source = {
              type = "github";
              url = "forrestchang/andrej-karpathy-skills";
            };
            flakeInput = marketplaceInputs.karpathy-skills;
          };
          # ponytail lives in nix-ai (input + tier file), same as karpathy-skills.
          "ponytail" = {
            source = {
              type = "github";
              url = "DietrichGebert/ponytail";
            };
            flakeInput = marketplaceInputs.ponytail;
          };
        };

      enabled = enabledPlugins // {
        # Host-specific opinion (was nix-darwin hosts/macbook-m4/home.nix):
        # playwright plugin disabled globally — only useful in specific
        # projects. playwright@claude-skills (skills-only, no MCP) stays
        # enabled via 04-community.nix.
        "playwright@claude-plugins-official" = false;
      };
      allowRuntimeInstall = true;
    };

    commands = {
      fromFlakeInputs = mkSourceEntries "${claude-cookbooks}/.claude/commands" cbCommands;
    };

    agents.fromFlakeInputs =
      (mkSourceEntries "${ai-assistant-instructions}/agentsmd/agents" aiAgents)
      ++ (mkSourceEntries "${claude-cookbooks}/.claude/agents" cbAgents);

    rules.fromFlakeInputs = mkSourceEntries "${ai-assistant-instructions}/agentsmd/rules" aiRules;

    rules.local = {
      "retrospective-report-location" = ./claude/rules/retrospective-report-location.md;
    };

    settings = {
      alwaysThinkingEnabled = true;
      cleanupPeriodDays = 180;
      env = import ./claude/settings-env.nix;

      permissions = {
        allow = formatters.claude.formatAllowed permissions;
        deny = formatters.claude.formatDenied permissions;
        ask = formatters.claude.formatAsk permissions;
      };

      skillOverrides =
        let
          file = "${ai-assistant-instructions}/agentsmd/settings/skill-overrides.json";
        in
        if builtins.pathExists file then (lib.importJSON file).skillOverrides or { } else { };

      additionalDirectories = import ./claude/settings-paths.nix;

      sandbox = {
        enabled = false;
      };
    };

    # Auto-mode classifier configuration (top-level `autoMode` in settings.json).
    # Prose rules describing trusted infrastructure (environment) plus the
    # classifier allow/soft_deny overrides, so routine internal actions
    # aren't flagged and destructive ones still ask. See ./claude/automode.nix.
    autoMode = import ./claude/automode.nix {
      inherit lib;
      userConfig = userConfig // {
        user = (userConfig.user or { }) // {
          fullName = userConfig.user.fullName or "JacobPEvans";
        };
      };
    };

    # MCP Servers - deployed to ~/.claude.json via home.activation.
    # Shared definitions are owned by modules/mcp and rendered per-client here.
    # Per-host overrides (disables + splunk) were previously in
    # nix-darwin/hosts/macbook-m4/home.nix; moved here as part of the
    # nix-claude-code migration so Claude config lives in nix-ai.
    mcpServers =
      let
        fromCatalog = lib.mapAttrs (_: normalizeClaudeMcpServer) config.programs.aiMcp.servers;
        # Disable MCP servers that duplicate built-in tools, are demo/test,
        # or are project-specific. Definitions stay (for type validation);
        # disabled = true excludes them from ~/.claude.json. Project-specific
        # servers re-enable per-project via .mcp.json.
        disabledServers = lib.genAttrs [
          "everything" # Demo/test — not useful in production
          "filesystem" # Duplicates built-in Read/Write/Glob/Edit tools
          "fetch" # Duplicates built-in WebFetch tool
          "git" # Duplicates built-in git via Bash(git:*)
          "github" # Duplicates github@claude-plugins-official plugin
          "cribl" # Project-specific — re-enable per-project
          "terraform" # Project-specific — re-enable per-project
          "cloudflare" # Not actively used — disable until needed
          "exa" # Not actively used — disable until needed
          "firecrawl" # Not actively used — disable until needed
          "docker" # Not actively used — disable until needed
        ] (name: (fromCatalog.${name} or { }) // { disabled = true; });
      in
      fromCatalog
      // disabledServers
      // {
        # Splunk MCP via doppler-mcp wrapper (TLS bypass for self-signed cert
        # is scoped inside splunk-mcp-connect, not here, to avoid leaking
        # NODE_TLS_REJECT_UNAUTHORIZED to doppler-mcp).
        splunk = {
          command = "doppler-mcp";
          args = [ "splunk-mcp-connect" ];
        };
      };

    statusline = {
      enable = true;
      # ccstatusline (sirmalloc/ccstatusline) — the statusline that was active
      # in nix-ai before the nix-claude-code migration. Pinned explicitly so it
      # does not fall back to nix-claude-code's powerline default.
      theme = "ccstatusline";
    };

    # Hooks: Event-driven automation for Claude Code.
    # captureSessionOutput wires postToolUse to the vendored capture script.
    # refreshMarketplaces wires sessionStart to the vendored refresh helper.
    # Both scripts live in nix-claude-code (modules/scripts/) post-PR2.
    hooks = {
      captureSessionOutput = true;
      refreshMarketplaces = true;
    };
  };
}
