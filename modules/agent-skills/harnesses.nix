# Harness registry — single source of truth for the shared-agent fan-out.
#
# Maps harness name -> skills directory and AGENTS.md file (relative to $HOME).
# Skill directories are symlinked to the root selected by
# programs.agentSkills.root. Adding a harness here is ONE line: the symlink,
# the legacy-copy cleanup, and the regression check (lib/checks/agent-skills.nix)
# are all generated from this attrset.
#
# Claude Code is intentionally absent: it consumes skills through its
# plugin/marketplace system, not through ~/.agents/skills.
# Codex is absent from both registries: it discovers ~/.codex/skills and
# ~/.agents/skills natively, and programs.codex.context already bakes AGENTS.md
# inline to ~/.codex/AGENTS.md. Creating a Codex symlink would make it scan the
# selected skill tree twice.
rec {
  # Skills directory fan-out — each entry is a directory path (relative to
  # $HOME) that gets symlinked to the selected canonical skill root.
  # Cursor is deliberately absent for the same reason as Codex: its own
  # discovery list already covers .codex/skills/ and .agents/skills/, so a
  # symlink here would make it scan the selected tree twice. Verified against
  # the installed build — see modules/cursor/default.nix.
  skills = {
    qwen = ".qwen/skills";
    # Read by the `agy` CLI: its binary references both ".gemini/config/skills"
    # and ".agents/skills" (verified against the installed build). The key name
    # is historical — this is agy's config dir, not a gemini-cli one, and there
    # is no gemini-cli module in this repo.
    gemini = ".gemini/config/skills";
    # The Antigravity IDE's own state directory. No consumer in this repo owns
    # it, and no installed Antigravity binary was found to reference the path —
    # but a composed-at-runtime path would not show up in that search, so this
    # is unproven-unused rather than proven-dead. Left in place: a dangling
    # symlink costs nothing, while removing a live skills root silently strips
    # the IDE of every shared skill. Confirm against a release note or the
    # running IDE before deleting.
    antigravity = ".gemini/antigravity/skills";
    antigravity-cli = ".gemini/antigravity-cli/skills";
    opencode = ".config/opencode/skills";
  };

  # AGENTS.md fan-out — each entry is a file path (relative to $HOME) that
  # gets symlinked to ~/.agents/AGENTS.md. Tools that natively load from
  # their own config dir find it without any extra configuration.
  agentsMd = {
    qwen = ".qwen/AGENTS.md";
    antigravity-cli = ".gemini/antigravity-cli/AGENTS.md";
    opencode = ".config/opencode/AGENTS.md";
  };
}
