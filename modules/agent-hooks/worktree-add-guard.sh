#!/usr/bin/env bash
# PreToolUse hook (Claude Code and Codex share this contract): denies
# `codex exec` without a prompt file on stdin and `git worktree add` outside
# `<repo>/.worktrees/` or `<repo>/.claude/worktrees/`.
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

# Inspect each command in a chain. The command-position anchor keeps text such
# as `grep "codex exec" file` from looking like a CLI invocation.
codex_exec_regex='^[[:space:]]*(([[:alpha:]_][[:alnum:]_]*=[^[:space:]]+)[[:space:]]+)*(([^[:space:]]*/)?env[[:space:]]+(([[:alpha:]_][[:alnum:]_]*=[^[:space:]]+|-i|--ignore-environment|--)[[:space:]]+)*)?((command|exec)[[:space:]]+)?([^[:space:]]*/)?codex[[:space:]]+exec([[:space:]]|$)'
git_command_prefix='^[[:space:]]*(([[:alpha:]_][[:alnum:]_]*=[^[:space:]]+)[[:space:]]+)*(([^[:space:]]*/)?env[[:space:]]+(([[:alpha:]_][[:alnum:]_]*=[^[:space:]]+|-i|--ignore-environment|--)[[:space:]]+)*)?((command|exec)[[:space:]]+)?([^[:space:]]*/)?git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?'
raw_branch_reason="Start branches with \`git town hack <name>\` (or the harness worktree); never from a local base."
base_merge_reason="Sync with \`git town sync\` (rebase); never merge the base into a PR branch."
stdin_file_regex='(^|[^<])<[[:space:]]*[^<[:space:]]'
segments="$(printf '%s\n' "$command" | sed -E 's/(&&|\|\||[;|&])/\n/g')"
while IFS= read -r segment; do
  # A prompt-file redirect keeps codex exec from waiting on an open, non-TTY stdin.
  if [[ "$segment" =~ $codex_exec_regex && ! "$segment" =~ $stdin_file_regex ]]; then
    deny "Run codex exec with its prompt on stdin from a file: codex exec [flags] - < <prompt-file> (see model-delegation.md)."
  fi

  [[ "$segment" =~ $git_command_prefix ]] || continue
  read -ra git_tokens <<<"$segment"

  # Find the executable after any command prefix, then skip git's optional
  # -C <path> pair before identifying the subcommand.
  git_index=-1
  for i in "${!git_tokens[@]}"; do
    case "${git_tokens[$i]}" in
    git | */git)
      git_index="$i"
      break
      ;;
    esac
  done
  [ "$git_index" -ge 0 ] || continue
  subcommand_index=$((git_index + 1))
  if [ "${git_tokens[$subcommand_index]:-}" = "-C" ]; then
    subcommand_index=$((subcommand_index + 2))
  fi
  git_subcommand="${git_tokens[$subcommand_index]:-}"
  git_args_index=$((subcommand_index + 1))

  case "$git_subcommand" in
  checkout)
    for ((i = git_args_index; i < ${#git_tokens[@]}; i++)); do
      case "${git_tokens[$i]}" in
      -b | -B | --branch | -b=* | -B=* | --branch=*) deny "$raw_branch_reason" ;;
      esac
    done
    ;;
  switch)
    for ((i = git_args_index; i < ${#git_tokens[@]}; i++)); do
      case "${git_tokens[$i]}" in
      -c | -C | --create | --force-create | -c=* | -C=* | --create=* | --force-create=*) deny "$raw_branch_reason" ;;
      esac
    done
    ;;
  branch)
    branch_has_argument=0
    branch_list_mode=0
    branch_safe_operation=0
    for ((i = git_args_index; i < ${#git_tokens[@]}; i++)); do
      case "${git_tokens[$i]}" in
      -d | -D | --delete | -m | -M | --move)
        branch_safe_operation=1
        ;;
      -l | --list | -a | --all | -r | --remotes | -v | -vv | --verbose | --show-current | --merged | --no-merged | --contains | --no-contains | --points-at | --format | --sort | --column | --omit-empty | --list=*)
        branch_list_mode=1
        ;;
      --format=* | --sort=* | --column=*)
        branch_list_mode=1
        ;;
      --)
        if [ "$((i + 1))" -lt "${#git_tokens[@]}" ]; then
          branch_has_argument=1
        fi
        ;;
      -* ) ;;
      *) branch_has_argument=1 ;;
      esac
    done
    if [ "$branch_has_argument" -eq 1 ] && [ "$branch_list_mode" -eq 0 ] && [ "$branch_safe_operation" -eq 0 ]; then
      deny "$raw_branch_reason"
    fi
    ;;
  merge | pull)
    pull_no_rebase=0
    if [ "$git_subcommand" = "pull" ]; then
      for ((i = git_args_index; i < ${#git_tokens[@]}; i++)); do
        [ "${git_tokens[$i]}" = "--no-rebase" ] && pull_no_rebase=1
      done
      [ "$pull_no_rebase" -eq 1 ] || continue
    fi

    for ((i = git_args_index; i < ${#git_tokens[@]}; i++)); do
      tok="${git_tokens[$i]}"
      case "$tok" in
      -m | --message | -F | --file | -s | --strategy | -X | --strategy-option | --exec | --upload-pack | --depth | --deepen | --shallow-since | --shallow-exclude | --jobs | --filter | --server-option)
        i=$((i + 1))
        ;;
      --)
        continue
        ;;
      -* ) ;;
      main | develop | origin/main | origin/develop | origin/HEAD)
        deny "$base_merge_reason"
        ;;
      esac
    done
    ;;
  esac
done <<<"$segments"

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

# Find "worktree add" and walk forward past flags to the target path and
# optional start-point, skipping the value of -b/-B/--reason.
target=""
startpoint=""
for i in "${!tokens[@]}"; do
  if [ "${tokens[$i]}" = "worktree" ] && [ "${tokens[$((i + 1))]:-}" = "add" ]; then
    j=$((i + 2))
    while [ "$j" -lt "${#tokens[@]}" ]; do
      tok="${tokens[$j]}"
      case "$tok" in
      -b | -B | --branch | --reason)
        j=$((j + 2))
        ;;
      --)
        j=$((j + 1))
        ;;
      -*)
        j=$((j + 1))
        ;;
      *)
        if [ -z "$target" ]; then
          target="$tok"
        else
          startpoint="$tok"
          break 2
        fi
        j=$((j + 1))
        ;;
      esac
    done
    break
  fi
done
[ -n "$target" ] || exit 0
case "$startpoint" in
origin/*) ;;
*) deny "$raw_branch_reason" ;;
esac

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
