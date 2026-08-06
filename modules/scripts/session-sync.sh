#!/usr/bin/env bash
# Push AI session history to a peer Mac so sessions resume on either machine.
# Called by the launchd agent in modules/session-sync.nix.
#
# Arguments: <rsync> <ssh> <remote> <log-dir> <lock-dir>
# then a "--paths" list, then a "--excludes" list.
#
# The peer runs whatever rsync is on its own PATH. Naming a specific one here
# would mean naming a Nix store path, which exists on this machine and not on
# the peer; the default negotiates with Apple's rsync and upgrades itself for
# free if the peer ever gets a newer one.
set -uo pipefail

rsync_bin="$1"
ssh_bin="$2"
remote="$3"
log_dir="$4"
lock_dir="$5"
shift 5

paths=()
excludes=()
bucket=""
for arg in "$@"; do
  case "$arg" in
    --paths) bucket="paths" ;;
    --excludes) bucket="excludes" ;;
    *) [ "$bucket" = "paths" ] && paths+=("$arg") || excludes+=("$arg") ;;
  esac
done

mkdir -p "$log_dir"
log="$log_dir/sync.log"

# mkdir is atomic, so it doubles as the lock. The first push moves gigabytes and
# can outrun the hourly interval; without this, runs would stack and fight over
# the same files. A stale lock older than 6h is assumed dead — a sync that long
# has failed, and never clearing it would silently stop syncing forever.
if ! mkdir "$lock_dir" 2>/dev/null; then
  if [ -n "$(find "$lock_dir" -maxdepth 0 -mmin +360 2>/dev/null)" ]; then
    echo "$(date -Iseconds) reclaiming stale lock" >>"$log"
    rmdir "$lock_dir" 2>/dev/null || true
    mkdir "$lock_dir" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

# A laptop is usually asleep, on another network, or awake but unreachable. None
# of those are failures worth reporting, so probe cheaply and leave quietly.
if ! "$ssh_bin" -o BatchMode=yes -o ConnectTimeout=10 "$remote" true 2>/dev/null; then
  echo "$(date -Iseconds) $remote unreachable, skipping" >>"$log"
  exit 0
fi

exclude_args=()
for e in "${excludes[@]}"; do exclude_args+=(--exclude "$e"); done

started=$(date +%s)
failed=0
for rel in "${paths[@]}"; do
  src="$HOME/$rel"
  [ -e "$src" ] || continue
  # --update is what makes this safe to run against a machine that is also
  # working: a session resumed on the peer is newer there, and must not be
  # reverted by this machine's older copy. No --delete for the same reason —
  # the peer's own sessions are not ours to remove.
  # --no-links is what keeps this from fighting Nix. Inside these directories
  # every symlink is home-manager's config pointing into /nix/store, and the
  # session data is all regular files. Copying a symlink would land a path that
  # names this machine's store on a machine that does not have it, and would
  # overwrite config the peer is supposed to get from its own generation.
  "$rsync_bin" --archive --no-links --update --partial --human-readable \
    -e "$ssh_bin -o BatchMode=yes -o ConnectTimeout=10" \
    "${exclude_args[@]}" \
    "$src/" "$remote:$rel/" >>"$log" 2>&1 || {
    rc=$?
    # 24 is "source files vanished mid-transfer", which is normal here: agents
    # rotate and rewrite session files constantly. Anything else is real.
    if [ "$rc" != "24" ]; then
      echo "$(date -Iseconds) rsync $rel failed rc=$rc" >>"$log"
      failed=1
    fi
  }
done

echo "$(date -Iseconds) sync finished in $(($(date +%s) - started))s failed=$failed" >>"$log"
exit "$failed"
