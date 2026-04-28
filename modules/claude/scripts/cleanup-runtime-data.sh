#!/usr/bin/env bash
# Runtime Data Cleanup for ~/.claude
#
# Prunes stale session artifacts that accumulate over time.
# Runs on every home-manager switch via orphan-cleanup.nix Phase 4.
#
# Usage: cleanup-runtime-data.sh <home_dir> <retention_days> <max_backups>
#
# Safety: reads active session PIDs from ~/.claude/sessions/*.json before
# touching anything. Files/dirs matching an active session UUID are skipped.

set -euo pipefail

if [[ -f "$(dirname "$0")/cleanup-common.sh" ]]; then
  # shellcheck source=cleanup-common.sh
  . "$(dirname "$0")/cleanup-common.sh"
else
  log_info() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" >&2; }
fi

HOME_DIR="${1:?HOME_DIR required}"
RETENTION_DAYS="${2:-30}"
MAX_BACKUPS="${3:-5}"

CLAUDE_DIR="${HOME_DIR}/.claude"

# ────────────────────────────────────────────────
# Active session detection
# ────────────────────────────────────────────────

ACTIVE_UUIDS=()

# Use find to enumerate session files — avoids ARG_MAX limits with many sessions.
# PID is encoded in the filename (e.g., 36922.json); check it with kill -0 to
# confirm the process is still running before treating the session as active.
while IFS= read -r session_file; do
  uuid=$(jq -r '.sessionId // .session_id // empty' "$session_file" 2>/dev/null)
  [[ -z "$uuid" ]] && continue
  pid="${session_file##*/}"
  pid="${pid%.json}"
  # Skip only numeric PIDs confirmed dead; non-numeric filenames are included conservatively
  if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then
    continue
  fi
  ACTIVE_UUIDS+=("$uuid")
done < <(find "${CLAUDE_DIR}/sessions" -maxdepth 1 -name "*.json" -type f 2>/dev/null)

log_info "Active sessions: ${#ACTIVE_UUIDS[@]}"

is_active_session() {
  local target="$1"
  for uuid in "${ACTIVE_UUIDS[@]}"; do
    [[ "$target" == *"$uuid"* ]] && return 0
  done
  return 1
}

# ────────────────────────────────────────────────
# Helpers: delete items older than a given age
# ────────────────────────────────────────────────

prune_dir_by_age() {
  local dir="$1"
  local label="$2"
  [[ -d "$dir" ]] || return 0

  local count=0
  while IFS= read -r -d $'\0' item; do
    is_active_session "$item" && continue
    rm -rf "$item"
    count=$((count + 1))
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)

  if [[ $count -gt 0 ]]; then
    log_info "Pruned $count stale $label entries"
  fi
}

prune_files_by_age() {
  local dir="$1"
  local label="$2"
  local days="$3"
  [[ -d "$dir" ]] || return 0

  local count=0
  while IFS= read -r -d $'\0' f; do
    rm -f "$f"
    count=$((count + 1))
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -mtime +"$days" -print0 2>/dev/null)
  if [[ $count -gt 0 ]]; then
    log_info "Pruned $count stale $label files"
  fi
}

# ────────────────────────────────────────────────
# 1. Telemetry — always delete (failed events never retry)
# ────────────────────────────────────────────────

if [[ -d "${CLAUDE_DIR}/telemetry" ]]; then
  count=0
  while IFS= read -r -d $'\0' f; do
    rm -f "$f"
    count=$((count + 1))
  done < <(find "${CLAUDE_DIR}/telemetry" -name "1p_failed_events*" -print0 2>/dev/null)
  if [[ $count -gt 0 ]]; then
    log_info "Removed $count failed telemetry events"
  fi
fi

# ────────────────────────────────────────────────
# 2. security_warnings_state_*.json — stale per-session files in ~/.claude root
# ────────────────────────────────────────────────

stale_warnings=0
while IFS= read -r -d $'\0' f; do
  is_active_session "$f" && continue
  rm -f "$f"
  stale_warnings=$((stale_warnings + 1))
done < <(find "${CLAUDE_DIR}" -maxdepth 1 -name "security_warnings_state_*.json" -print0 2>/dev/null)
if [[ $stale_warnings -gt 0 ]]; then
  log_info "Removed $stale_warnings stale security_warnings_state files"
fi

# ────────────────────────────────────────────────
# 3. projects/ + session-keyed runtime data dirs
# ────────────────────────────────────────────────

prune_dir_by_age "${CLAUDE_DIR}/projects"    "project session"
prune_dir_by_age "${CLAUDE_DIR}/todos"          "todo"
prune_dir_by_age "${CLAUDE_DIR}/file-history"   "file-history"
prune_dir_by_age "${CLAUDE_DIR}/shell-snapshots" "shell-snapshot"
prune_dir_by_age "${CLAUDE_DIR}/session-env"    "session-env"
prune_dir_by_age "${CLAUDE_DIR}/paste-cache"    "paste-cache"
prune_dir_by_age "${CLAUDE_DIR}/plans"          "plan"
prune_dir_by_age "${CLAUDE_DIR}/tasks"          "task"

# ────────────────────────────────────────────────
# 4. backups — keep only the newest MAX_BACKUPS
# ────────────────────────────────────────────────

backups_dir="${CLAUDE_DIR}/backups"
if [[ -d "$backups_dir" ]]; then
  # Use -print (not -print0) + LC_ALL=C sort: backup filenames have no spaces/newlines
  # and sort -z is a GNU extension not available on macOS BSD sort.
  mapfile -t backup_files < <(
    find "$backups_dir" -maxdepth 1 -name ".claude.json.backup.*" -print 2>/dev/null |
    LC_ALL=C sort
  )
  excess=$(( ${#backup_files[@]} - MAX_BACKUPS ))
  if [[ $excess -gt 0 ]]; then
    for (( i=0; i<excess; i++ )); do
      rm -f "${backup_files[$i]}"
    done
    log_info "Removed $excess old backups (kept $MAX_BACKUPS)"
  fi
fi

# ────────────────────────────────────────────────
# 5. statsig/ — feature flag caches, 7-day retention
# ────────────────────────────────────────────────

prune_files_by_age "${CLAUDE_DIR}/statsig" "statsig cache" 7

# ────────────────────────────────────────────────
# 6. logs/ — delete log files older than RETENTION_DAYS
# ────────────────────────────────────────────────

prune_files_by_age "${CLAUDE_DIR}/logs" "log" "$RETENTION_DAYS"

log_info "Runtime data cleanup complete (retention: ${RETENTION_DAYS}d, max backups: ${MAX_BACKUPS})"
