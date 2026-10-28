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

expect_deny_reason() {
  local label="$1" input="$2" expected="$3"
  local result
  result=$(printf '%s' "$input" | bash "$script")
  if ! printf '%s' "$result" | jq -e --arg expected "$expected" \
    '.hookSpecificOutput.permissionDecision == "deny" and .hookSpecificOutput.permissionDecisionReason == $expected' >/dev/null; then
    echo "FAIL ($label): expected deny reason '$expected', got: $result" >&2
    fail=1
  else
    echo "PASS ($label): denied with requested reason"
  fi
}

raw_branch_reason="Start branches with \`git town hack <name>\` (or the harness worktree); never from a local base."
base_merge_reason="Sync with \`git town sync\` (rebase); never merge the base into a PR branch."

expect_allow "relative under .worktrees" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add .worktrees/x origin/develop"},"cwd":"/repo"}'

expect_allow "absolute under .worktrees" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add /repo/.worktrees/x origin/develop"},"cwd":"/repo"}'

expect_allow "-b flag before target" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add -b feat .worktrees/x origin/develop"},"cwd":"/repo"}'

expect_deny "relative sibling via .." \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add ../foo origin/develop"},"cwd":"/repo"}'

expect_deny "git -C with unrelated target" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo worktree add /tmp/x origin/develop"},"cwd":"/other"}'

expect_deny "chained: earlier command, denied worktree add" \
  '{"tool_name":"Bash","tool_input":{"command":"git status && git worktree add /tmp/x origin/develop"},"cwd":"/repo"}'

expect_allow "chained: earlier command, allowed worktree add" \
  '{"tool_name":"Bash","tool_input":{"command":"git fetch origin && git worktree add .worktrees/y origin/develop"},"cwd":"/repo"}'

expect_deny "escape via .. after the allowed dir" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add .worktrees/../../elsewhere origin/develop"},"cwd":"/repo"}'

expect_allow "relative under .claude/worktrees" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add .claude/worktrees/x origin/develop"},"cwd":"/repo"}'

expect_deny_reason "worktree start-point defaults to local HEAD" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add .worktrees/x"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_deny_reason "worktree start-point is a local base" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add .worktrees/x develop"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_allow "worktree start-point is origin/HEAD" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add --no-track -b feat .worktrees/x origin/HEAD"},"cwd":"/repo"}'

expect_allow "worktree start-point is origin/develop" \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree add --no-track -b feat .worktrees/x origin/develop"},"cwd":"/repo"}'

expect_allow "no worktree add in command" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"/repo"}'

expect_allow "git town hack" \
  '{"tool_name":"Bash","tool_input":{"command":"git town hack x"},"cwd":"/repo"}'

expect_allow "git town sync" \
  '{"tool_name":"Bash","tool_input":{"command":"git town sync"},"cwd":"/repo"}'

expect_allow "git fetch" \
  '{"tool_name":"Bash","tool_input":{"command":"git fetch origin"},"cwd":"/repo"}'

expect_allow "git rebase origin/develop" \
  '{"tool_name":"Bash","tool_input":{"command":"git rebase origin/develop"},"cwd":"/repo"}'

expect_deny_reason "checkout -b" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feat/new-branch"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_deny_reason "checkout -B" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -B feat/new-branch"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_deny_reason "switch -c" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch -c feat/new-branch"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_deny_reason "switch -C" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch -C feat/new-branch"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_deny_reason "switch --create" \
  '{"tool_name":"Bash","tool_input":{"command":"git switch --create feat/new-branch"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_deny_reason "git -C switch --create" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo switch --create feat/new-branch"},"cwd":"/other"}' \
  "$raw_branch_reason"

expect_deny_reason "branch creation" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch feat/new-branch"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_deny_reason "branch creation with tracking" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --track feat/new-branch origin/develop"},"cwd":"/repo"}' \
  "$raw_branch_reason"

expect_allow "branch list without arguments" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch"},"cwd":"/repo"}'

expect_allow "branch list all" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -a"},"cwd":"/repo"}'

expect_allow "branch list explicit" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --list"},"cwd":"/repo"}'

expect_allow "branch show current" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --show-current"},"cwd":"/repo"}'

expect_allow "branch delete short" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -d x"},"cwd":"/repo"}'

expect_allow "branch delete force" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -D x"},"cwd":"/repo"}'

expect_allow "branch delete long" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --delete x"},"cwd":"/repo"}'

expect_allow "branch rename" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch -m old new"},"cwd":"/repo"}'

expect_allow "branch rename long" \
  '{"tool_name":"Bash","tool_input":{"command":"git branch --move old new"},"cwd":"/repo"}'

expect_deny_reason "merge main" \
  '{"tool_name":"Bash","tool_input":{"command":"git merge main"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "merge develop" \
  '{"tool_name":"Bash","tool_input":{"command":"git merge develop"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "merge origin/main" \
  '{"tool_name":"Bash","tool_input":{"command":"git merge origin/main"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "merge origin/develop" \
  '{"tool_name":"Bash","tool_input":{"command":"git merge origin/develop"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "merge origin/HEAD" \
  '{"tool_name":"Bash","tool_input":{"command":"git merge origin/HEAD"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "git -C merge base" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo merge --no-edit origin/develop"},"cwd":"/other"}' \
  "$base_merge_reason"

expect_allow "merge feature branch" \
  '{"tool_name":"Bash","tool_input":{"command":"git merge feature/topic"},"cwd":"/repo"}'

expect_deny_reason "pull --no-rebase main" \
  '{"tool_name":"Bash","tool_input":{"command":"git pull --no-rebase main"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "pull --no-rebase develop" \
  '{"tool_name":"Bash","tool_input":{"command":"git pull --no-rebase develop"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "pull --no-rebase origin/main" \
  '{"tool_name":"Bash","tool_input":{"command":"git pull --no-rebase origin/main"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "pull --no-rebase origin/develop" \
  '{"tool_name":"Bash","tool_input":{"command":"git pull --no-rebase origin/develop"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "pull --no-rebase origin/HEAD" \
  '{"tool_name":"Bash","tool_input":{"command":"git pull --no-rebase origin/HEAD"},"cwd":"/repo"}' \
  "$base_merge_reason"

expect_deny_reason "git -C pull --no-rebase base" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo pull --no-rebase origin develop"},"cwd":"/other"}' \
  "$base_merge_reason"

expect_allow "pull --no-rebase feature branch" \
  '{"tool_name":"Bash","tool_input":{"command":"git pull --no-rebase origin feature/topic"},"cwd":"/repo"}'

expect_allow "pull with default rebase policy" \
  '{"tool_name":"Bash","tool_input":{"command":"git pull origin/develop"},"cwd":"/repo"}'

expect_allow "codex version command" \
  '{"tool_name":"Bash","tool_input":{"command":"codex --version"},"cwd":"/repo"}'

expect_allow "quoted grep pattern" \
  '{"tool_name":"Bash","tool_input":{"command":"grep \"codex exec\" file"},"cwd":"/repo"}'

codex_exec_reason='Run codex exec with its prompt on stdin from a file: codex exec [flags] - < <prompt-file> (see model-delegation.md).'
expect_deny_reason "codex exec" \
  '{"tool_name":"Bash","tool_input":{"command":"codex exec -"},"cwd":"/repo"}' \
  "$codex_exec_reason"

expect_deny_reason "codex exec after a chained command" \
  '{"tool_name":"Bash","tool_input":{"command":"echo before && codex exec -"},"cwd":"/repo"}' \
  "$codex_exec_reason"

expect_deny_reason "codex exec after a semicolon" \
  '{"tool_name":"Bash","tool_input":{"command":"echo before; codex exec -"},"cwd":"/repo"}' \
  "$codex_exec_reason"

expect_deny_reason "codex exec in a pipeline" \
  '{"tool_name":"Bash","tool_input":{"command":"printf before | env CODEX_HOME=/tmp/codex codex exec -"},"cwd":"/repo"}' \
  "$codex_exec_reason"

expect_deny_reason "codex exec by full path" \
  '{"tool_name":"Bash","tool_input":{"command":"/nix/store/abc-codex/bin/codex exec -"},"cwd":"/repo"}' \
  "$codex_exec_reason"

expect_deny_reason "codex exec with assignment prefix" \
  '{"tool_name":"Bash","tool_input":{"command":"CODEX_HOME=/tmp/codex codex exec -"},"cwd":"/repo"}' \
  "$codex_exec_reason"

expect_deny_reason "codex exec with env prefix and full path" \
  '{"tool_name":"Bash","tool_input":{"command":"env CODEX_HOME=/tmp/codex /opt/homebrew/bin/codex exec -"},"cwd":"/repo"}' \
  "$codex_exec_reason"

expect_allow "codex exec with a prompt file on stdin" \
  '{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=x codex exec -s workspace-write --add-dir /repo/.worktrees/a -C /repo/.worktrees/a - < /tmp/prompt.md"},"cwd":"/repo"}'

expect_allow "codex exec with a prompt file after a chained command" \
  '{"tool_name":"Bash","tool_input":{"command":"cd /repo && codex exec -</tmp/prompt.md"},"cwd":"/repo"}'

expect_deny_reason "codex exec with a heredoc prompt" \
  '{"tool_name":"Bash","tool_input":{"command":"codex exec - <<EOF"},"cwd":"/repo"}' \
  "$codex_exec_reason"

expect_allow "non-Bash tool" \
  '{"tool_name":"Read","tool_input":{"file_path":"/x"},"cwd":"/repo"}'

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "worktree-add-guard: all cases behave as expected"
touch "$out"
