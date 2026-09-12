#!/usr/bin/env bash
# Test body for the worktree-add-guard check (lib/checks/lint.nix).
# Runs modules/agent-hooks/worktree-add-guard.sh directly against the
# stdin shapes Claude Code and Codex send for PreToolUse, asserting each
# case allows (empty stdout, exit 0) or denies (deny JSON, exit 0).
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"
script="${SRC}/modules/agent-hooks/worktree-add-guard.sh"

fail=0

expect_allow() {
  local label="$1" input="$2"
  local result
  result=$(printf '%s' "$input" | bash "$script")
  if [ -n "$result" ]; then
    echo "FAIL ($label): expected allow (empty stdout), got: $result" >&2
    fail=1
  else
    echo "PASS ($label): allowed"
  fi
}

expect_deny() {
  local label="$1" input="$2"
  local result
  result=$(printf '%s' "$input" | bash "$script")
  if ! printf '%s' "$result" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    echo "FAIL ($label): expected a deny decision, got: $result" >&2
    fail=1
  else
    echo "PASS ($label): denied"
  fi
}

expect_allow "relative under .worktrees" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add .worktrees/x"},"cwd":"/repo"}'

expect_allow "absolute under .worktrees" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add /repo/.worktrees/x"},"cwd":"/repo"}'

expect_allow "-b flag before target" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add -b feat .worktrees/x"},"cwd":"/repo"}'

expect_deny "relative sibling via .." \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add ../foo"},"cwd":"/repo"}'

expect_deny "git -C with unrelated target" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo worktree add /tmp/x"},"cwd":"/other"}'

expect_allow "relative under .claude/worktrees" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add .claude/worktrees/x"},"cwd":"/repo"}'

expect_allow "no worktree add in command" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"/repo"}'

expect_allow "non-Bash tool" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"},"cwd":"/repo"}'

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "worktree-add-guard: all cases behave as expected"
touch "$out"
