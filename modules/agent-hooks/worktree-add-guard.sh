#!/usr/bin/env bash
# PreToolUse hook (Claude Code and Codex share this contract): denies
# `git worktree add` when the destination is not under `<repo>/.worktrees/`
# or `<repo>/.claude/worktrees/`. See modules/agent-hooks/default.nix.
#
# Contract: stdin is one JSON object with tool_name, tool_input.command
# (string) and cwd. Allow by printing nothing and exiting 0. Deny by
# printing the hookSpecificOutput JSON below and exiting 0 — a nonzero
# exit is a hook error to the harness, not a decision.
set -euo pipefail

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

input="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)" || {
  echo "worktree-add-guard: unparseable stdin JSON, allowing" >&2
  exit 0
}
[ "$tool_name" = "Bash" ] || exit 0

command="$(jq -r '.tool_input.command // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -n "$command" ] || exit 0

# Chained commands: split on &&, ||, ;, | and take the first segment that
# actually invokes `git ... worktree add ...` — later segments are not our
# concern, and a segment before the guard-relevant one may contain any of
# those separators as ordinary text without affecting this scan.
segment="$(printf '%s\n' "$command" | sed -E 's/(&&|\|\||[;|])/\n/g' |
  grep -m1 -E '(^|[[:space:]])git([[:space:]]|$).*\bworktree\b[[:space:]]+add\b' || true)"
[ -n "$segment" ] || exit 0

read -ra tokens <<<"$segment"

# git -C <dir> ... worktree add — resolve relative targets against <dir>
# instead of cwd when present.
git_c_dir=""
for i in "${!tokens[@]}"; do
  if [ "${tokens[$i]}" = "-C" ]; then
    git_c_dir="${tokens[$((i + 1))]:-}"
    break
  fi
  [ "${tokens[$i]}" = "worktree" ] && break
done

# Find "worktree add" and walk forward past flags to the target path,
# skipping the value of -b/-B/--reason.
target=""
for i in "${!tokens[@]}"; do
  if [ "${tokens[$i]}" = "worktree" ] && [ "${tokens[$((i + 1))]:-}" = "add" ]; then
    j=$((i + 2))
    while [ "$j" -lt "${#tokens[@]}" ]; do
      tok="${tokens[$j]}"
      case "$tok" in
      -b | -B | --reason)
        j=$((j + 2))
        ;;
      -*)
        j=$((j + 1))
        ;;
      *)
        target="$tok"
        break 2
        ;;
      esac
    done
    break
  fi
done
[ -n "$target" ] || exit 0

# Resolve to an absolute path without requiring the directory to exist.
case "$target" in
/*) abs="$target" ;;
*)
  base="${git_c_dir:-$cwd}"
  case "$base" in
  /*) : ;;
  *) base="${cwd%/}/$base" ;;
  esac
  abs="${base%/}/$target"
  ;;
esac

# Collapse "//", "/./" and "x/../" until stable — a plain string
# normalization, no filesystem access.
prev=""
while [ "$prev" != "$abs" ]; do
  prev="$abs"
  abs="$(printf '%s' "$abs" | sed -E 's#/{2,}#/#g; s#/\./#/#g; s#(^|/)[^/]+/\.\./#\1#')"
done

case "$abs" in
*/.worktrees/* | */.claude/worktrees/*) exit 0 ;;
*) deny "worktree must be created under <repo>/.worktrees/ (got: $abs)" ;;
esac
