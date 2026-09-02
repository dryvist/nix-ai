# shellcheck shell=bash
# Sourced by direnv before every .envrc: link the skill groups this repository
# declares in AGENTS.md into .agents/skills and .claude/skills. No-op outside
# a repository or without a declaration; never fails the environment.
if command -v agent-skill-groups >/dev/null 2>&1; then
  agent-skill-groups link >&2 || true
fi
