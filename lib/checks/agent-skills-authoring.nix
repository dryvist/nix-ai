# Official authoring skill sources and cross-harness delivery maps.
{
  pkgs,
  hmConfig,
  hmConfigAgentSkillsShared,
  marketplaceInputs,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  sources = import ../../modules/agent-skills/sources.nix;
  cfg = hmConfig.config.programs.agentSkills;
  sharedCfg = hmConfigAgentSkillsShared.config.programs.agentSkills;
  pluginDevInput = marketplaceInputs.${sources.claude-plugins-official.input};
  pluginDevSkillsPath = "${pluginDevInput}/plugins/plugin-dev/skills";
  pluginDevSkills = builtins.attrNames (
    pkgs.lib.filterAttrs (
      name: type: type == "directory" && builtins.pathExists "${pluginDevSkillsPath}/${name}/SKILL.md"
    ) (builtins.readDir pluginDevSkillsPath)
  );
  anthropicInput = marketplaceInputs.${sources.anthropic-agent-skills.input};
  anthropicAuthoringSkills = pkgs.lib.subtractLists sources.anthropic-agent-skills.claude sources.anthropic-agent-skills.skills;
  authoringSources =
    pkgs.lib.genAttrs pluginDevSkills (name: "${pluginDevSkillsPath}/${name}")
    // pkgs.lib.genAttrs anthropicAuthoringSkills (name: "${anthropicInput}/skills/${name}");
  langfuseInput = marketplaceInputs.${sources.langfuse-skills.input};
  langfuseSources = pkgs.lib.genAttrs sources.langfuse-skills.claude (
    name: "${langfuseInput}/skills/${name}"
  );
  matchesSources =
    root: paths: sources:
    builtins.all (name: toString (paths."${root}/${name}" or "") == sources.${name}) (
      builtins.attrNames sources
    );
in
{
  agent-skills-authoring-delivery =
    let
      plugins = hmConfig.config.programs.claude.plugins.enabled;
      anthropicSkills = builtins.filter (
        skill: pkgs.lib.hasPrefix "${marketplaceInputs.anthropic-agent-skills}/" (toString skill.source)
      ) cfg.fromFlakeInputs;
    in
    assert plugins."plugin-dev@claude-plugins-official";
    assert plugins."example-skills@anthropic-agent-skills";
    assert !plugins."document-skills@anthropic-agent-skills";
    assert !plugins."claude-api@anthropic-agent-skills";
    assert anthropicSkills == [ ];
    assert builtins.all (name: builtins.elem name cfg.categories.authoring) (
      builtins.attrNames authoringSources
    );
    assert matchesSources ".codex/skills" cfg.deployedSkillPaths (authoringSources // langfuseSources);
    assert matchesSources ".agents/skills" sharedCfg.deployedSkillPaths (
      authoringSources // langfuseSources
    );
    assert matchesSources ".claude/skills" cfg.deployedSkillPaths langfuseSources;
    assert cfg.deployedSkillPaths ? ".codex/skills/plugin-dev-create-plugin";
    helpers.mkMarker "check-agent-skills-authoring-delivery" "Authoring and Langfuse skill directories delivered from official inputs";
}
