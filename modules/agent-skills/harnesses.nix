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
# Codex and OpenCode are absent from the skills registry: both discover
# ~/.agents/skills natively, and programs.codex.context already bakes AGENTS.md
# inline to ~/.codex/AGENTS.md. Creating a Codex symlink would make it scan the
# selected skill tree twice.
rec {
  # Skills directory fan-out — each entry is a directory path (relative to
  # $HOME) that gets symlinked to the selected canonical skill root.
  skills = {
    qwen = ".qwen/skills";
    antigravity = ".gemini/antigravity/skills";
    antigravity-cli = ".gemini/antigravity-cli/skills";
    gemini = ".gemini/config/skills";
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
