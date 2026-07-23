# Harness registry — single source of truth for the shared-agent fan-out.
#
# Maps harness name -> skills directory and AGENTS.md file (relative to $HOME)
# that are symlinked to the canonical ~/.agents/. Adding a harness here is ONE
# line: the symlink, the legacy-copy cleanup, and the regression check
# (lib/checks/agent-skills.nix) are all generated from this attrset.
#
# Claude Code is intentionally absent: it consumes skills through its
# plugin/marketplace system, not through ~/.agents/skills.
# Codex is absent from agentsMd: its native programs.codex.context already
# bakes AGENTS.md inline to ~/.codex/AGENTS.md.
rec {
  # Skills directory fan-out — each entry is a directory path (relative to
  # $HOME) that gets symlinked to ~/.agents/skills.
  skills = {
    codex = ".codex/skills";
    qwen = ".qwen/skills";
    antigravity = ".gemini/antigravity/skills";
    antigravity-cli = ".gemini/antigravity-cli/skills";
    gemini = ".gemini/config/skills";
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
