# Regression check for the per-repository skill linker (modules/agent-skills/repo-link).
{ pkgs }:
{
  # The repo-level linker: links, prunes, leaves real directories alone, and
  # is idempotent, exercised against a throwaway repository and manifest.
  agent-skills-repo-link =
    let
      linker = pkgs.callPackage ../../modules/agent-skills/repo-link/package.nix { };
    in
    pkgs.runCommand "check-agent-skills-repo-link"
      {
        nativeBuildInputs = [
          linker
          pkgs.git
        ];
      }
      ''
        set -euo pipefail
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME" skills/a skills/b skills/c
        touch skills/a/SKILL.md skills/b/SKILL.md skills/c/SKILL.md
        a="$PWD/skills/a" b="$PWD/skills/b" c="$PWD/skills/c"
        # Managed links are recognised by their /nix/store prefix.
        store="/nix/store/00000000000000000000000000000000-skills"
        printf '{"core":{"a":"%s/a","b":"%s/b"},"homelab":{"c":"%s/c"}}' \
          "$store" "$store" "$store" > "$HOME/GROUPS.json"
        export AGENT_SKILL_GROUPS_FILE="$HOME/GROUPS.json"
        git init -q repo && cd repo
        git config user.email t@example.invalid && git config user.name t
        printf -- '---\nskill-groups: [core, homelab]\n---\n' > AGENTS.md
        mkdir -p .claude/skills/own && touch .claude/skills/own/SKILL.md
        agent-skill-groups link
        [ "$(readlink .agents/skills/a)" = "$store/a" ]
        [ "$(readlink .claude/skills/c)" = "$store/c" ]
        [ -f .claude/skills/own/SKILL.md ]
        grep -qx '.agents/skills/' .git/info/exclude
        printf -- '---\nskill-groups:\n  - core\n---\n' > AGENTS.md
        agent-skill-groups link
        [ ! -e .agents/skills/c ] && [ ! -L .agents/skills/c ]
        [ -L .agents/skills/a ]
        before="$(ls -la .agents/skills .claude/skills)"
        agent-skill-groups link
        [ "$before" = "$(ls -la .agents/skills .claude/skills)" ]
        printf -- '---\nskill-groups: [nope]\n---\n' > AGENTS.md
        agent-skill-groups link 2>err.txt
        grep -q "unknown group 'nope'" err.txt
        [ ! -d .agents/skills ]
        agent-skill-groups status | grep -q '^groups: nope'
        touch "$out"
      '';
}
