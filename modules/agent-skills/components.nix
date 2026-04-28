# Agent Skills Components
#
# Manages shared skill deployment to ~/.agents/skills.
{ config, lib, ... }:

let
  cfg = config.programs.agentSkills;
  homeDir = config.home.homeDirectory;
  skillDir = source: builtins.dirOf source;

  mkSkillFiles =
    components:
    builtins.listToAttrs (
      map (c: {
        name = ".agents/skills/${c.name}";
        value = {
          source = skillDir c.source;
          force = true;
        };
      }) components
    );

  mkLocalSkills =
    locals:
    lib.concatMapAttrs (name: path: {
      ".agents/skills/${name}" = {
        source = skillDir path;
        force = true;
      };
    }) locals;
in
{
  config = lib.mkIf cfg.enable {
    home = {
      activation.cleanupLegacySkillCopies = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        cleanup_skill_tree() {
          root="$1"

          [ -d "$root" ] || return 0

          find "$root" -mindepth 1 -maxdepth 1 -type d -print | while IFS= read -r skill_dir; do
            skill_file="$skill_dir/SKILL.md"
            if [ -L "$skill_file" ] && [ "$(find "$skill_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ]; then
              target=$(readlink "$skill_file")
              case "$target" in
                /nix/store/*)
                  $DRY_RUN_CMD rm -rf "$skill_dir"
                  ;;
              esac
            fi
          done

          rmdir "$root" 2>/dev/null || true
        }

        cleanup_skill_tree "${homeDir}/.agents/skills"
        cleanup_skill_tree "${homeDir}/.codex/skills"
        cleanup_skill_tree "${homeDir}/.gemini/skills"
      '';

      file = {
        ".agents/.keep".text = ''
          # Managed by Nix - programs.agentSkills module
        '';
      }
      // mkSkillFiles cfg.fromFlakeInputs
      // mkLocalSkills cfg.local;
    };
  };
}
