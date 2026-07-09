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

          [ -d "$root" ] && [ ! -L "$root" ] || return 0

          find "$root" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d $'\0' skill_dir; do
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

          # Prune per-skill symlinks whose store target no longer exists. A skill
          # removed from the flake input set between generations leaves a dangling
          # link here: it is a symlink (not a -type d), so the legacy sweep above
          # skips it, and home-manager's generation diff does not remove it either.
          find "$root" -mindepth 1 -maxdepth 1 -type l -print0 | while IFS= read -r -d $'\0' link; do
            [ -e "$link" ] || $DRY_RUN_CMD rm -f "$link"
          done

          $DRY_RUN_CMD rmdir "$root" 2>/dev/null || true
        }

        cleanup_skill_tree "${homeDir}/.agents/skills"
        cleanup_skill_tree "${homeDir}/.codex/skills"
        cleanup_skill_tree "${homeDir}/.antigravity-cli/skills"
        cleanup_skill_tree "${homeDir}/.qwen/skills"
      '';

      file = {
        ".agents/.keep".text = ''
          # Managed by Nix - programs.agentSkills module
        '';
        ".gemini/antigravity/skills".source =
          config.lib.file.mkOutOfStoreSymlink "${homeDir}/.agents/skills";
        ".gemini/antigravity-cli/skills".source =
          config.lib.file.mkOutOfStoreSymlink "${homeDir}/.agents/skills";
        ".gemini/config/skills".source = config.lib.file.mkOutOfStoreSymlink "${homeDir}/.agents/skills";
        ".codex/skills".source = config.lib.file.mkOutOfStoreSymlink "${homeDir}/.agents/skills";
        ".qwen/skills".source = config.lib.file.mkOutOfStoreSymlink "${homeDir}/.agents/skills";
      }
      // mkSkillFiles cfg.fromFlakeInputs
      // mkLocalSkills cfg.local;
    };
  };
}
