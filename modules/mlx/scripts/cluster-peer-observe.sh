# shellcheck shell=bash
# Rank progress observations for the link watcher.
#
# Concatenated into the link watcher. Function definitions read the CLUSTER_*
# environment at call time.
#
# Consumed environment:
#   CLUSTER_RANK_PROGRESS_LOG        the one log token progress is counted from
#   CLUSTER_STATE_FILE               link-state file; its directory is the
#                                    shared marker dir

read_int() {
  local value=0
  [ -f "$1" ] && value="$(cat "$1")"
  case "$value" in
    '' | *[!0-9]*) value=0 ;;
  esac
  printf '%s' "$value"
}

# Tokens produced by real traffic since the last read. Counts matches only in
# appended bytes, so a hit is a progress edge and the check stays cheap on a
# log newsyslog lets grow to 10 MB. A shrunken file means newsyslog rotated it,
# so the offset restarts at zero instead of reading past the end forever.
new_progress_lines() {
  local f="${CLUSTER_RANK_PROGRESS_LOG:-}" offset_file size off
  { [ -n "$f" ] && [ -f "$f" ]; } || {
    printf '0'
    return 0
  }
  offset_file="$(dirname "${CLUSTER_STATE_FILE}")/peer-progress-offset"
  size="$(/usr/bin/stat -f %z "$f" 2> /dev/null || wc -c < "$f")"
  off="$(read_int "$offset_file")"
  [ "$size" -lt "$off" ] && off=0
  printf '%s\n' "$size" > "$offset_file"
  tail -c "+$((off + 1))" -- "$f" 2> /dev/null |
    grep -cE 'tokens-per-sec|Prompt:|Generation:' || true
}
