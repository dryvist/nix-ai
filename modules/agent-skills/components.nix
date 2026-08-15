# Agent Skills Components
#
# Manages shared skill deployment to one Codex-visible canonical root.
{ config, lib, ... }:

let
  cfg = config.programs.agentSkills;
  homeDir = config.home.homeDirectory;
  skillDir = source: builtins.dirOf source;
  skillRoots = {
    codex = ".codex/skills";
    agents = ".agents/skills";
  };
  skillRoot = skillRoots.${cfg.root};
  inactiveSkillRoot = skillRoots.${if cfg.root == "codex" then "agents" else "codex"};

  # Harness fan-out: one registry generates the symlinks, the cleanup sweep,
  # and (via lib/checks/agent-skills.nix) the regression coverage.
  harnesses = import ./harnesses.nix;
  harnessSkillDirs = builtins.attrValues harnesses.skills;
  harnessSymlinks = lib.genAttrs harnessSkillDirs (_: {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDir}/${skillRoot}";
  });

  # AGENTS.md fan-out: each tool's native global path → ~/.agents/AGENTS.md
  harnessAgentsMdSymlinks = lib.mapAttrs' (_name: relPath: {
    name = relPath;
    value = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDir}/.agents/AGENTS.md";
    };
  }) harnesses.agentsMd;

  # Names-only manifest (descriptions would force IFD on wrapped-command
  # skills). Harnesses without a native skill loader (Copilot, cecli) are
  # pointed at this file from their instruction context, so any file-capable
  # agent can discover and follow the shared skills.
  skillIndex = ''
    # Shared Agent Skills

    Reusable skills live in `~/${skillRoot}/<name>/SKILL.md`. When a task
    matches a skill below, read its SKILL.md and follow it.

    ${lib.concatMapStrings (n: "- ${n}\n") (
      lib.unique (map (c: c.name) cfg.fromFlakeInputs ++ builtins.attrNames cfg.local)
    )}'';

  mkSkillFiles =
    components:
    builtins.listToAttrs (
      map (c: {
        name = "${skillRoot}/${c.name}";
        value = {
          source = skillDir c.source;
          force = true;
        };
      }) components
    );

  mkLocalSkills =
    locals:
    lib.concatMapAttrs (name: path: {
      "${skillRoot}/${name}" = {
        source = skillDir path;
        force = true;
      };
    }) locals;
in
{
  config = lib.mkIf cfg.enable {
    home = {
      activation.cleanupLegacySkillCopies = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        cleanup_legacy_root_link() {
          root="$1"

          [ -L "$root" ] || return 0
          target=$(readlink "$root")
          case "$target" in
            /nix/store/*)
              $DRY_RUN_CMD rm -f "$root"
              ;;
          esac
        }

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

        # Older generations linked ~/.codex/skills to ~/.agents/skills. Codex
        # discovers both roots itself, so remove that managed alias before
        # deploying the one root selected by programs.agentSkills.root.
        cleanup_legacy_root_link "${homeDir}/.codex/skills"
        cleanup_legacy_root_link "${homeDir}/.agents/skills"

        cleanup_skill_tree "${homeDir}/${skillRoot}"
        # Legacy pre-registry location (module once deployed here directly).
        cleanup_skill_tree "${homeDir}/.antigravity-cli/skills"
        ${lib.concatMapStrings (dir: ''
          cleanup_skill_tree "${homeDir}/${dir}"
        '') harnessSkillDirs}
      '';

      activation.cleanupInactiveSkillRoot = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        # Home Manager removes the previous generation's managed entries. Drop
        # the now-empty alternate root so Codex never scans both locations.
        $DRY_RUN_CMD rmdir "${homeDir}/${inactiveSkillRoot}" 2>/dev/null || true
      '';

      file = {
        "${skillRoot}/INDEX.md".text = skillIndex;
      }
      // harnessSymlinks
      // harnessAgentsMdSymlinks
      // mkSkillFiles cfg.fromFlakeInputs
      // mkLocalSkills cfg.local;
    };
  };
}
