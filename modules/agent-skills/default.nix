# Agent Skills Configuration Module
#
# Declarative configuration for shared cross-tool skills.
# Discovers plugin skills and deploys them to the configured canonical root.
# SKILL.md discovery itself lives in ./discovery.nix.
{
  config,
  lib,
  pkgs,
  marketplaceInputs,
  awesome-claude-skills,
  ...
}:

let
  pluginTiers = import ../claude/plugins {
    inherit lib marketplaceInputs;
  };
  inherit (pluginTiers) enabledPlugins;

  sharedSkills = import ./discovery.nix {
    inherit
      lib
      pkgs
      enabledPlugins
      ;
    # Select Anthropic and Orca skills below instead of discovering their whole bundles.
    marketplaceInputs = builtins.removeAttrs marketplaceInputs [
      "anthropic-agent-skills"
      "orca-skills"
    ];
  };
in
{
  imports = [
    ./options.nix
    ./components.nix

    # Legacy option paths (kept for compatibility during migration).
    #
    # The codex aliases that previously lived here were removed: home-manager
    # 26.05 introduced a native `programs.codex.skills` leaf option (codex-only,
    # deploys to ~/.codex/skills), so child aliases under that path collided with
    # it ("type ... does not support nested options"). nix-ai's cross-tool feature
    # is `programs.agentSkills.*`; nothing in this
    # repo set the legacy codex paths, so dropping them loses no configuration.
    (lib.mkRenamedOptionModule
      [
        "programs"
        "antigravity-cli"
        "skills"
        "fromFlakeInputs"
      ]
      [
        "programs"
        "agentSkills"
        "fromFlakeInputs"
      ]
    )
    (lib.mkRenamedOptionModule
      [
        "programs"
        "antigravity-cli"
        "skills"
        "local"
      ]
      [
        "programs"
        "agentSkills"
        "local"
      ]
    )
  ];

  config = {
    programs.agentSkills = {
      enable = lib.mkDefault true;
      fromFlakeInputs = lib.mkDefault sharedSkills;

      # Targeted Anthropic sources preserve each complete skill directory.
      # file-organizer matches no discovery pattern.
      local = {
        file-organizer = "${awesome-claude-skills}/file-organizer/SKILL.md";
        frontend-design = "${marketplaceInputs.anthropic-agent-skills}/skills/frontend-design/SKILL.md";
        canvas-design = "${marketplaceInputs.anthropic-agent-skills}/skills/canvas-design/SKILL.md";
        skill-creator = "${marketplaceInputs.anthropic-agent-skills}/skills/skill-creator/SKILL.md";
        mcp-builder = "${marketplaceInputs.anthropic-agent-skills}/skills/mcp-builder/SKILL.md";
        # These two Orca skills are selected by name so its other skills are not deployed.
        orca-emulator = "${marketplaceInputs.orca-skills}/skills/orca-emulator/SKILL.md";
        orchestration = "${marketplaceInputs.orca-skills}/skills/orchestration/SKILL.md";
      };

      # Category map for the generated INDEX.md and, through `groups` below,
      # the deployment groups `activeGroups` gates. Every deployed skill is
      # named exactly once; the regression check fails on an orphan.
      #
      #   core      — engineering workflow every repository needs
      #   nix       — Nix, nix-darwin, home-manager, macOS system config
      #   homelab   — Proxmox, OpenTofu, Ansible, Terrakube, OpenBao, network
      #   ai        — LLM serving, routing, Hugging Face, delegation to Codex
      #   docs      — documentation sites, diagrams, long-form writing
      #   research  — code and paper search, reading, summarising
      #   workspace — office formats, design, art, personal organisation
      categories = lib.mkDefault (import ./categories.nix);

      # Deployment groups. `categories` only drives the generated INDEX.md
      # headings; `groups` is what `activeGroups` actually gates. Spelling the
      # same map twice would leave two copies to keep in sync, so derive one
      # from the other — a host overriding categories gets matching groups for
      # free and the two cannot drift apart.
      #
      # Safe as a restrictive filter since every deployed skill is named above;
      # the agent-skills check fails the build the moment one is not.
      groups = lib.mkDefault config.programs.agentSkills.categories;

      # B6 "topic-scoped skill groups": `iac`, `security`, `observability`, and
      # `splunk` are opt-in per repository (repo-link/agent-skill-groups.sh links
      # them in when the repo's AGENTS.md declares the group), not part of the
      # global always-installed set. Every other category still deploys
      # everywhere — unchanged default. A host that already sets activeGroups
      # keeps its own list (mkDefault).
      activeGroups = lib.mkDefault (
        builtins.filter (g: g != "iac" && g != "security" && g != "observability" && g != "splunk") (
          builtins.attrNames config.programs.agentSkills.categories
        )
      );
    };
  };
}
