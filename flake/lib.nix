# CI-friendly and cross-flake `lib` outputs for nix-ai.
#
# Extracted from flake.nix to keep that file under the repo file-size budget
# (.file-size.yml: warn 6 KB / error 12 KB) without dropping the explanatory
# comments. Same split pattern as flake/home-manager-modules.nix — the flake
# wires this in as `lib = import ./flake/lib.nix { ... }`, so the public
# `nix-ai.lib.*` attribute set is byte-for-byte unchanged.
{
  nixpkgs,
  nix-claude-code,
  nix-codex,
  nix-agy,
  homebrewNix,
}:
{
  ci = {
    # Render the same settings.json shape nix-ai's pre-PR3 fixture
    # produced (top-level $schema, alwaysThinkingEnabled,
    # enabledPlugins, extraKnownMarketplaces, permissions{allow,
    # ask,deny,additionalDirectories,defaultMode}, statusLine).
    # Built from nix-claude-code.lib helpers so the marketplace
    # catalog and permission shape stay in one repo.
    claudeSettingsJson =
      let
        inherit (nixpkgs) lib;
        ncc = nix-claude-code.lib;
        aiCommon = import ../modules/common {
          inherit nix-claude-code lib;
          config = {
            home.homeDirectory = "/home/user";
          };
        };
        inherit (aiCommon) permissions formatters;
        pluginTiers = import ../modules/claude/plugins {
          inherit lib;
          marketplaceInputs = nix-claude-code.inputs;
        };
        # nix-claude-code's catalog lacks jacobpevans-cc-plugins
        # (PR2 oversight) and karpathy-skills (added on main after
        # PR3 started). Splice them in to keep nix-ai's CI output
        # in lockstep with pre-PR3 behavior.
        augmentedCatalog = ncc.marketplaceCatalog.marketplaces // {
          "jacobpevans-cc-plugins" = {
            source = {
              type = "github";
              url = "JacobPEvans/claude-code-plugins";
            };
          };
          "karpathy-skills" = {
            source = {
              type = "github";
              url = "forrestchang/andrej-karpathy-skills";
            };
          };
          "ponytail" = {
            source = {
              type = "github";
              url = "DietrichGebert/ponytail";
            };
          };
        };
        extraKnownMarketplaces = lib.mapAttrs ncc.claudeRegistry.toClaudeMarketplaceFormat augmentedCatalog;
      in
      builtins.toJSON {
        "$schema" = "https://json.schemastore.org/claude-code-settings.json";
        alwaysThinkingEnabled = true;
        inherit (pluginTiers) enabledPlugins;
        inherit extraKnownMarketplaces;
        permissions = {
          allow = formatters.claude.formatAllowed permissions;
          deny = formatters.claude.formatDenied permissions;
          ask = [ ];
          additionalDirectories = [ "~/.claude/" ];
          defaultMode = "auto";
        };
        statusLine = {
          type = "command";
          command = "/home/user/.claude/statusline-command.sh";
        };
      };

    codexRules =
      let
        aiCommon = import ../modules/common {
          inherit nix-claude-code;
          inherit (nixpkgs) lib;
          config = {
            home.homeDirectory = "/home/user";
          };
        };
        inherit (aiCommon) permissions formatters;
      in
      formatters.codex.formatRulesFile permissions;
  };

  # Versions registry (Renovate-managed pin source-of-truth)
  versions = import ../lib/versions.nix;

  # Named project-scoped plugin packs (api, terraform, proxmox, obsidian, …).
  # Pure attrset so foreign consumers can read the groupings without the module
  # system. The home module (modules/claude/skill-packs.nix) renders these to
  # ~/.config/ai-packs/<name>.json for the `ai-pack` importer. Single source of
  # truth: modules/claude/plugins/packs.nix. See docs/architecture/plugin-scoping.md.
  skillPacks = import ../modules/claude/plugins/packs.nix;

  # Role-name → physical mlx-community/* model ID registry.
  # Exported as a plain attrset so foreign consumers (e.g. a homelab
  # gateway config) can consume it without importing the
  # home-manager module system. The module at
  # modules/ai-stack/default.nix uses this same file as its option
  # default — one source of truth.
  aiStackModels = import ../lib/ai-stack-models.nix;

  # AI-tool Homebrew packages. nix-darwin passes its injected, default-off
  # capability attrset once; package names and package types stay in nix-ai.
  # Source of truth: lib/homebrew.nix (its taps also drive trust.json).
  homebrewFor =
    capabilities:
    let
      enabled =
        packages:
        nixpkgs.lib.concatLists (
          nixpkgs.lib.mapAttrsToList (
            capability: values: nixpkgs.lib.optionals (capabilities.${capability} or false) values
          ) packages
        );
    in
    {
      inherit (homebrewNix) taps;
      brews = enabled homebrewNix.brews;
      casks = enabled homebrewNix.casks;
    };

  # Shared permission + formatter engine. Exposed for cross-flake consumers
  # (e.g., nix-ai-claude) so the source of truth for tool-agnostic command
  # permissions stays in this flake. Callers pass { lib, config,
  # nix-claude-code, excludeDenyCategories?, excludeDenyCommands? }
  # and receive { permissions, formatters } — see modules/common/default.nix.
  aiCommon = import ../modules/common;

  # Autonomy profiles (interactive / autonomous / ci) — tool-agnostic
  # deployment postures. See modules/common/profiles.nix for the model.
  profiles = import ../modules/common/profiles.nix { inherit (nixpkgs) lib; };

  # Autonomous-profile config renderers for agent container images
  # (dryvist/nix-agent-sandbox). Pure strings, never written to a host
  # filesystem by any home-manager code path.
  #
  # COMPOSED from the per-CLI leaves rather than rendered here. Each leaf owns
  # its own tool's config and takes the shared residualDeny as a parameter, so
  # there is exactly one renderer per CLI instead of a copy here and a copy
  # there. That duplication was not cosmetic: the same invalid
  # `defaultApprovalMode` bug shipped in two copies and had to be fixed twice
  # (nix-ai#1464, dryvist/nix-agy#1). See nix-ai#1465.
  #
  # `files` is the contract nix-agent-sandbox bakes (it mapAttrs over this
  # opaquely), so the composed set is asserted byte-identical to the previous
  # local render by lib/checks/autonomous-profile.nix.
  #
  # nix-claude-code additionally renders `.claude.json`
  # (remoteControlAtStartup). It is deliberately NOT included here: adding a
  # file would change the image contract, which is a separate decision from
  # this behaviour-neutral refactor.
  renderAutonomous =
    let
      # Imported here rather than reusing the `profiles` attribute below:
      # that is a sibling in this (non-recursive) attrset, so it is not in
      # scope. Same pure import, same value.
      inherit (import ../modules/common/profiles.nix { inherit (nixpkgs) lib; })
        residualDeny
        ;
      args = {
        inherit (nixpkgs) lib;
        inherit residualDeny;
      };
      claude = import "${nix-claude-code}/lib/render-autonomous.nix" args;
      codex = import "${nix-codex}/lib/render-autonomous.nix" args;
      agy = import "${nix-agy}/lib/render-autonomous.nix" args;
    in
    {
      inherit residualDeny;
      claudeSettingsJson = claude.settingsJson;
      codexConfigToml = codex.configToml;
      codexRules = codex.rules;
      inherit (agy) geminiSettingsJson geminiPolicyToml;
      files = {
        ".claude/settings.json" = claude.settingsJson;
        ".codex/config.toml" = codex.configToml;
        ".codex/rules/default.rules" = codex.rules;
        ".gemini/settings.json" = agy.geminiSettingsJson;
        ".gemini/policies/autonomous.toml" = agy.geminiPolicyToml;
      };
    };
}
