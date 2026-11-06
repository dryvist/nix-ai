# Official authoring skill sources and cross-harness delivery maps.
{
  pkgs,
  hmConfig,
  hmConfigAgentSkillsShared,
  marketplaceInputs,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.agentSkills;
  sharedCfg = hmConfigAgentSkillsShared.config.programs.agentSkills;
  pluginDevSkills = [
    "agent-development"
    "command-development"
    "hook-development"
    "mcp-integration"
    "plugin-settings"
    "plugin-structure"
    "skill-development"
  ];
  authoringSources =
    pkgs.lib.genAttrs pluginDevSkills (
      name: "${marketplaceInputs.claude-plugins-official}/plugins/plugin-dev/skills/${name}"
    )
    // pkgs.lib.genAttrs [ "skill-creator" "mcp-builder" ] (
      name: "${marketplaceInputs.anthropic-agent-skills}/skills/${name}"
    );
  langfuseSources = pkgs.lib.genAttrs [ "langfuse" "migrate-to-langfuse" ] (
    name: "${marketplaceInputs.langfuse-skills}/skills/${name}"
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
