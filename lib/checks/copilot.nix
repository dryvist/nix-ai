# GitHub Copilot CLI regression tests
{ pkgs, hmConfig }:
let
  skillsDir = hmConfig.config.programs.agentSkills.skillsDir;
  homeFiles = hmConfig.config.home.file;
  instructionsPath = ".copilot/copilot-instructions.md";
in
{
  # Copilot has no native skill loader and no MCP wiring: its entire link to
  # the shared skill set is one instruction file naming a directory. That
  # pointer was hardcoded to ".agents/skills" while the default root is
  # "codex" — and lib/checks/agent-skills.nix asserts the agents root is NOT
  # deployed — so Copilot was pointed at a manifest guaranteed not to exist.
  # Nothing caught it because Copilot had no check file at all.
  copilot-skill-manifest-path =
    let
      indexPath = "${skillsDir}/INDEX.md";
    in
    assert
      builtins.hasAttr instructionsPath homeFiles
      || throw "Copilot instructions not deployed at ${instructionsPath}";
    assert
      builtins.hasAttr indexPath homeFiles
      || throw "Copilot instructions name ${indexPath}, which is not deployed";
    pkgs.runCommand "check-copilot-skill-manifest-path"
      {
        text = homeFiles.${instructionsPath}.text;
        passAsFile = [ "text" ];
        nativeBuildInputs = [ pkgs.gnugrep ];
      }
      ''
        grep -q "~/${skillsDir}/INDEX.md" "$textPath" \
          || { echo "Copilot instructions do not name ~/${skillsDir}/INDEX.md" >&2; exit 1; }

        # The inactive root must never be named: it is deliberately not
        # deployed, so citing it sends Copilot to a path that cannot resolve.
        inactive=$(if [ "${skillsDir}" = ".codex/skills" ]; then echo ".agents/skills"; else echo ".codex/skills"; fi)
        if grep -q "$inactive" "$textPath"; then
          echo "Copilot instructions name the inactive skill root $inactive" >&2
          exit 1
        fi

        touch $out
      '';

  # trusted_folders is the whole of Copilot's config surface; an empty list
  # means every directory prompts, which reads as "Copilot is broken".
  copilot-trusted-folders =
    let
      configPath = ".copilot/config.json";
    in
    assert
      builtins.hasAttr configPath homeFiles || throw "Copilot config not deployed at ${configPath}";
    pkgs.runCommand "check-copilot-trusted-folders"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -e '.trusted_folders | type == "array" and length > 0' \
          ${homeFiles.${configPath}.source} > /dev/null \
          || { echo "Copilot config has no trusted_folders" >&2; exit 1; }
        touch $out
      '';
}
