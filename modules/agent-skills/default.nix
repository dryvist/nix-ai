# Agent Skills Configuration Module
#
# Declarative configuration for shared cross-tool skills.
# Discovers plugin skills and deploys them to ~/.agents/skills.
{
  lib,
  pkgs,
  marketplaceInputs,
  ...
}:

let
  # Discovers SKILL.md files from plugin repos.
  # Pattern: <plugin>/skills/<skill-name>/SKILL.md
  discoverSkills =
    input:
    let
      topDirs = lib.filterAttrs (_: type: type == "directory") (builtins.readDir input);
      pluginSkills =
        pluginName:
        let
          skillsPath = "${input}/${pluginName}/skills";
          hasSkills = builtins.pathExists skillsPath;
          skillDirs =
            if hasSkills then
              lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsPath)
            else
              { };
        in
        lib.mapAttrsToList
          (skillName: _: {
            name = skillName;
            source = "${skillsPath}/${skillName}/SKILL.md";
          })
          (
            lib.filterAttrs (skillName: _: builtins.pathExists "${skillsPath}/${skillName}/SKILL.md") skillDirs
          );
    in
    lib.concatMap pluginSkills (builtins.attrNames topDirs);

  # Translates Claude commands (commands/*.md) dynamically into Agent Skills (SKILL.md).
  # Pattern: <plugin>/commands/<command-name>.md
  discoverClaudeCommands =
    input:
    let
      topDirs = lib.filterAttrs (_: type: type == "directory") (builtins.readDir input);
      pluginCommands =
        pluginName:
        let
          commandsPath = "${input}/${pluginName}/commands";
          hasCommands = builtins.pathExists commandsPath;
          commandFiles =
            if hasCommands then
              lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (
                builtins.readDir commandsPath
              )
            else
              { };
        in
        lib.mapAttrsToList (
          fileName: _:
          let
            commandName = lib.removeSuffix ".md" fileName;
            skillName = "${pluginName}-${commandName}";
            originalFile = "${commandsPath}/${fileName}";

            wrappedSkillDir = pkgs.runCommand "wrap-claude-command-${skillName}" { } ''
              mkdir -p $out
              cat << 'EOF' > $out/SKILL.md
              ---
              name: ${skillName}
              description: Claude plugin command imported from ${pluginName}/${commandName}.
              ---

              # `${skillName}`

              This skill was automatically imported from the Claude command `${pluginName}:${commandName}`.

              <instructions>
              Please read the following original Claude command specification and fulfill its intent.
              If the specification contains syntax like `!` followed by a shell command (e.g. `!git status`), you MUST execute that command using your bash/shell tools to gather the necessary context before proceeding.

              <original_command>
              EOF

              cat ${originalFile} >> $out/SKILL.md

              cat << 'EOF' >> $out/SKILL.md
              </original_command>
              </instructions>
              EOF
            '';
          in
          {
            name = skillName;
            source = "${wrappedSkillDir}/SKILL.md";
          }
        ) commandFiles;
    in
    lib.concatMap pluginCommands (builtins.attrNames topDirs);

  # Discovers SKILL.md files from a flat skills/ directory at the repo root.
  # Pattern: <repo>/skills/<skill-name>/SKILL.md
  # Used for marketplaces like huggingface/skills that store skills at the top level.
  discoverFlatSkills =
    input:
    let
      skillsPath = "${input}/skills";
    in
    if builtins.pathExists skillsPath then
      lib.mapAttrsToList
        (name: _: {
          inherit name;
          source = "${skillsPath}/${name}/SKILL.md";
        })
        (
          lib.filterAttrs (
            name: type: type == "directory" && builtins.pathExists "${skillsPath}/${name}/SKILL.md"
          ) (builtins.readDir skillsPath)
        )
    else
      [ ];

  # Discovers SKILL.md files from a bare .claude/skills/ directory.
  # Pattern: <repo>/.claude/skills/<skill-name>/SKILL.md
  discoverDotClaudeSkills =
    input:
    let
      skillsPath = "${input}/.claude/skills";
      hasSkills = builtins.pathExists skillsPath;
      skillDirs =
        if hasSkills then
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsPath)
        else
          { };
    in
    lib.mapAttrsToList (name: _: {
      inherit name;
      source = "${skillsPath}/${name}/SKILL.md";
    }) (lib.filterAttrs (name: _: builtins.pathExists "${skillsPath}/${name}/SKILL.md") skillDirs);

  # Skills from JacobPEvans/claude-code-plugins (tool-agnostic markdown)
  # Plus VisiCore cribl-pack-validator (bare .claude/skills/ layout)
  # Plus Hugging Face Hub skills (flat skills/<n>/SKILL.md layout)
  # Plus official Claude plugin skills and translated commands
  sharedSkills =
    discoverSkills marketplaceInputs.jacobpevans-cc-plugins
    ++ discoverDotClaudeSkills marketplaceInputs.vct-cribl-pack-validator-skills
    ++ discoverFlatSkills marketplaceInputs.huggingface-skills
    ++ discoverSkills "${marketplaceInputs.claude-plugins-official}/plugins"
    ++ discoverSkills "${marketplaceInputs.claude-plugins-official}/external_plugins"
    ++ discoverClaudeCommands "${marketplaceInputs.claude-plugins-official}/plugins"
    ++ discoverClaudeCommands "${marketplaceInputs.claude-plugins-official}/external_plugins";
in
{
  imports = [
    ./options.nix
    ./components.nix

    # Legacy option paths (kept for compatibility during migration).
    (lib.mkRenamedOptionModule
      [
        "programs"
        "codex"
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
        "codex"
        "skills"
        "local"
      ]
      [
        "programs"
        "agentSkills"
        "local"
      ]
    )
    (lib.mkRenamedOptionModule
      [
        "programs"
        "gemini"
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
        "gemini"
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
    };
  };
}
