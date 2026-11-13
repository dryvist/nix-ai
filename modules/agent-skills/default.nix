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
  skillSourceRoots,
  ...
}:

let
  sources = import ./sources.nix;
  pluginTiers = import ../claude/plugins {
    inherit lib marketplaceInputs;
  };
  inherit (pluginTiers) enabledPlugins;

  selectedSources = lib.filterAttrs (_: source: builtins.isList source.skills) sources;
  discoveredInputs = builtins.removeAttrs marketplaceInputs (builtins.attrNames selectedSources);

  skillFileCandidates = sourceName: skillName: [
    "${skillSourceRoots.${sourceName}}/skills/${skillName}/SKILL.md"
    "${skillSourceRoots.${sourceName}}/${skillName}/SKILL.md"
  ];
  matchingSkillFiles =
    sourceName: skillName:
    builtins.filter builtins.pathExists (skillFileCandidates sourceName skillName);
  skillFile =
    sourceName: skillName:
    let
      candidates = skillFileCandidates sourceName skillName;
      matches = matchingSkillFiles sourceName skillName;
    in
    if matches == [ ] then builtins.head candidates else builtins.head matches;

  selectedSkillRefs = lib.concatMap (
    sourceName:
    map (name: {
      inherit name sourceName;
    }) sources.${sourceName}.skills
  ) (builtins.attrNames selectedSources);
  namedSkillRefs = lib.concatMap (
    sourceName:
    let
      source = sources.${sourceName};
      explicitNames = if builtins.isList source.skills then source.skills else [ ];
    in
    map (name: {
      inherit name sourceName;
    }) (lib.unique (explicitNames ++ source.claude))
  ) (builtins.attrNames sources);
  invalidNamedSkills = builtins.filter (
    skill:
    builtins.length (matchingSkillFiles skill.sourceName skill.name) != 1
    || (
      builtins.isList sources.${skill.sourceName}.skills
      && !(builtins.elem skill.name sources.${skill.sourceName}.skills)
    )
  ) namedSkillRefs;

  sharedSkills = import ./discovery.nix {
    inherit
      lib
      pkgs
      enabledPlugins
      ;
    marketplaceInputs = discoveredInputs;
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
    assertions = [
      {
        assertion = invalidNamedSkills == [ ];
        message = "Agent Skills source table names must resolve to skill directories containing SKILL.md: ${builtins.toJSON invalidNamedSkills}";
      }
    ];

    programs.agentSkills = {
      enable = lib.mkDefault true;
      fromFlakeInputs = lib.mkDefault sharedSkills;

      local = lib.listToAttrs (
        map (skill: {
          inherit (skill) name;
          value = skillFile skill.sourceName skill.name;
        }) selectedSkillRefs
      );

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
