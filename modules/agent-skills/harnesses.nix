# Harness registry — single source of truth for the shared-skill fan-out.
#
# Maps harness name -> skills directory (relative to $HOME) that is symlinked
# to the canonical ~/.agents/skills. Adding a harness here is ONE line: the
# symlink, the legacy-copy cleanup, and the regression check
# (lib/checks/agent-skills.nix) are all generated from this attrset.
#
# Claude Code is intentionally absent: it consumes skills through its
# plugin/marketplace system, not through ~/.agents/skills.
{
  codex = ".codex/skills";
  qwen = ".qwen/skills";
  antigravity = ".gemini/antigravity/skills";
  antigravity-cli = ".gemini/antigravity-cli/skills";
  gemini = ".gemini/config/skills";
  opencode = ".config/opencode/skills";
}
