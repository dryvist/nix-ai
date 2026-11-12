# Repository-specific Claude plugin settings are regular Home Manager files.
{
  pkgs,
  hmConfig,
  hmConfigClaudeRepoGroups,
}:
let
  plainFiles = hmConfig.config.home.file;
  groupedFiles = hmConfigClaudeRepoGroups.config.home.file;
  repoOnePath = "git/public/repo-one/.claude/settings.json";
  repoOneWorktreePath = "git/worktrees/repo-one/.claude/settings.json";
  repoTwoPath = "git/public/repo-two/.claude/settings.json";
  repoOne = builtins.fromJSON groupedFiles.${repoOnePath}.text;
  repoTwo = builtins.fromJSON groupedFiles.${repoTwoPath}.text;
  knownPluginIds = builtins.attrNames hmConfigClaudeRepoGroups.config.programs.claude.plugins.enabled;
  repoOnePluginIds = [ "typescript-lsp@claude-plugins-official" ];
  repoTwoPluginIds = [ "estate-lsp@jacobpevans-cc-plugins" ];
  localSettingsFiles = builtins.filter (
    path: pkgs.lib.hasSuffix "/.claude/settings.local.json" path
  ) (builtins.attrNames groupedFiles);
in
{
  claude-repo-groups =
    assert builtins.seq hmConfigClaudeRepoGroups.activationPackage true;
    assert !(groupedFiles.${repoOnePath}.force or false);
    assert !(groupedFiles.${repoTwoPath}.force or false);
    assert !(builtins.hasAttr repoOnePath plainFiles);
    assert !(builtins.hasAttr repoTwoPath plainFiles);
    assert builtins.hasAttr repoOnePath groupedFiles;
    assert builtins.hasAttr repoOneWorktreePath groupedFiles;
    assert builtins.hasAttr repoTwoPath groupedFiles;
    assert localSettingsFiles == [ ];
    assert groupedFiles.${repoOnePath}.text == groupedFiles.${repoOneWorktreePath}.text;
    assert builtins.attrNames repoOne.enabledPlugins == knownPluginIds;
    assert builtins.attrNames repoTwo.enabledPlugins == knownPluginIds;
    assert builtins.all (
      pluginId: repoOne.enabledPlugins.${pluginId} == builtins.elem pluginId repoOnePluginIds
    ) knownPluginIds;
    assert builtins.all (
      pluginId: repoTwo.enabledPlugins.${pluginId} == builtins.elem pluginId repoTwoPluginIds
    ) knownPluginIds;
    assert groupedFiles.${repoOnePath}.text != groupedFiles.${repoTwoPath}.text;
    pkgs.runCommand "check-claude-repo-groups" { } ''
      touch $out
    '';
}
