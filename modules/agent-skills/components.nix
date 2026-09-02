# Agent Skills Components
#
# Manages shared skill deployment to one Codex-visible canonical root.
{
  config,
  lib,
  pkgs,
  ...
}:

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
  # and (via lib/checks/agent-skills.nix) the regression coverage. harnesses.nix
  # stays the static default registry. OpenCode has no skills entry (it reads
  # ~/.agents/skills natively — a mirrored symlink would scan the tree twice),
  # but its AGENTS.md entry is re-derived from `opencodeConfigDir` so a
  # relocated opencode config dir still gets the shared AGENTS.md.
  harnesses = (import ./harnesses.nix) // {
    agentsMd = (import ./harnesses.nix).agentsMd // {
      opencode = "${cfg.opencodeConfigDir}/AGENTS.md";
    };
  };
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
  #
  # Grouped by category so the list stays navigable as it grows. A skill listed
  # under two categories appears twice on purpose — the reader arrives from one
  # domain or the other and should find it either way.
  # Group gating — THE single filter point. `activeGroups = null` deploys
  # everything (the compatible default); a list deploys exactly the union of
  # the named groups. Everything downstream (home.file entries, INDEX.md,
  # categories) derives from the deployed* sets, so the gate cannot drift.
  activeSkillNames =
    if cfg.activeGroups == null then
      null
    else
      lib.unique (lib.concatMap (g: cfg.groups.${g}) cfg.activeGroups);
  skillActive = name: activeSkillNames == null || lib.elem name activeSkillNames;
  deployedFlakeInputs = builtins.filter (c: skillActive c.name) cfg.fromFlakeInputs;
  deployedLocal = lib.filterAttrs (name: _: skillActive name) cfg.local;

  allSkillNames = lib.unique (
    map (c: c.name) deployedFlakeInputs ++ builtins.attrNames deployedLocal
  );

  # Only categories that actually match a deployed skill become a heading, so a
  # category naming a skill from a removed input silently disappears instead of
  # rendering an empty section.
  categorized = lib.filterAttrs (_: names: names != [ ]) (
    lib.mapAttrs (_: names: lib.intersectLists names allSkillNames) cfg.categories
  );
  uncategorized = lib.subtractLists (lib.unique (lib.concatLists (builtins.attrValues categorized))) allSkillNames;

  renderSection = title: names: ''
    ## ${title}

    ${lib.concatMapStrings (n: "- ${n}\n") (lib.sort (a: b: a < b) names)}
  '';

  skillIndex = ''
    # Shared Agent Skills

    Reusable skills live in `~/${skillRoot}/<name>/SKILL.md`. When a task
    matches a skill below, read its SKILL.md and follow it. A skill may appear
    under more than one category.

    ${lib.concatStrings (lib.mapAttrsToList renderSection categorized)}${
      lib.optionalString (uncategorized != [ ]) (renderSection "Uncategorized" uncategorized)
    }'';

  # Machine-readable map for repo-level tooling: group -> name -> skill
  # directory, for EVERY known skill, not only the deployed ones. A host that
  # gates to one group still needs the others' paths so a repository can link
  # them; the store paths exist whether or not the host deploys them.
  skillSources =
    builtins.listToAttrs (map (c: lib.nameValuePair c.name (skillDir c.source)) cfg.fromFlakeInputs)
    // lib.mapAttrs (_: skillDir) cfg.local;
  groupsJson = builtins.toJSON (
    lib.mapAttrs (
      _: names:
      lib.genAttrs (builtins.filter (n: skillSources ? ${n}) names) (n: toString skillSources.${n})
    ) cfg.groups
  );

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
    assertions = [
      {
        assertion = cfg.activeGroups == null || builtins.all (g: cfg.groups ? ${g}) cfg.activeGroups;
        # `or [ ]` does not null-coalesce — activeGroups defaults to an explicit
        # null, so the filter must guard it or forcing this message crashes eval.
        message =
          "programs.agentSkills.activeGroups names undefined group(s): "
          + builtins.toJSON (
            builtins.filter (g: !(cfg.groups ? ${g})) (
              if cfg.activeGroups == null then [ ] else cfg.activeGroups
            )
          );
      }
    ];

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
        # OpenCode reads ~/.agents/skills itself; the managed alias is retired.
        cleanup_legacy_root_link "${homeDir}/.config/opencode/skills"
        ${lib.concatMapStrings (dir: ''
          cleanup_skill_tree "${homeDir}/${dir}"
        '') harnessSkillDirs}
      '';

      activation.cleanupInactiveSkillRoot = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        inactive_root="${homeDir}/${inactiveSkillRoot}"

        # A real directory in the alternate root (notably Codex's .system)
        # prevents Home Manager from removing stale links from its previous
        # generation. Remove only links owned by that generation; preserve
        # native and user-managed content.
        if [ -d "$inactive_root" ] && [ ! -L "$inactive_root" ]; then
          find "$inactive_root" -mindepth 1 -maxdepth 1 -type l -print0 | while IFS= read -r -d $'\0' link; do
            target=$(readlink "$link")
            case "$target" in
              /nix/store/*-home-manager-files/${inactiveSkillRoot}/*)
                $DRY_RUN_CMD rm -f "$link"
                ;;
            esac
          done
        fi

        $DRY_RUN_CMD rmdir "$inactive_root" 2>/dev/null || true
      '';

      # Repo-level layer: links a repository's declared groups into its own
      # skill trees on every direnv load (see repo-link/).
      packages = [ (pkgs.callPackage ./repo-link/package.nix { }) ];

      file = {
        "${skillRoot}/INDEX.md".text = skillIndex;
        "${skillRoot}/GROUPS.json".text = groupsJson;
        ".config/direnv/lib/agent-skill-groups.sh".source = ./repo-link/direnv-lib.sh;
      }
      // harnessSymlinks
      // harnessAgentsMdSymlinks
      // mkSkillFiles deployedFlakeInputs
      // mkLocalSkills deployedLocal;
    };
  };
}
