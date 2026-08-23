#!/usr/bin/env bash
# THE CHECK THAT FAILS IF A REFUSAL AFTER QUIESCE LEAVES SERVING DOWN.
#
# quiesce_normal_serving runs (kills in-flight Hermes requests, see its own
# header) BEFORE rank_start_room_ok is checked and before the kickstart is
# issued. Either can still refuse — insufficient memory even after quiescing,
# or `launchctl kickstart` itself failing — and both used to return there,
# leaving standalone serving down for an attempt that never even started a
# rank. This pins that both refusal paths call restore_normal_serving before
# falling through, and that a successful room-check + kickstart does NOT
# restore (the rank is what serves next, not standalone).
#
# A THIRD PATH REACHES THE SAME STATE FROM A LATER TICK. rank_start_preconditions_ok
# can pass on the tick that quiesced and refuse on the next one, and that refusal
# writes no halt — so nothing else restores and the host serves neither a rank
# nor standalone. This also pins that branch: it restores exactly ONCE per
# quiesce (the marker is the edge), never while a rank process survives, and
# never when this watcher did not quiesce in the first place.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — the QUIESCE-THEN-START BLOCK and the REFUSAL RESTORE BLOCK are
#           EXTRACTED FROM THE SHIPPED cluster-link-watcher.sh between their
#           own comment markers and executed, so a drift in either shipped
#           sequence fails here.
#   STUB  — quiesce_normal_serving, rank_start_room_ok, restore_normal_serving,
#           rank_process_running and launchctl are stubbed to drive each branch
#           deterministically; each one's own behaviour is pinned by its own
#           test file (test-mem-headroom.sh, test-serving-restore.sh).
#
# Usage:
#   WATCHER=… bash test-quiesce-restore.sh
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

watcher="${WATCHER:?set WATCHER to cluster-link-watcher.sh}"

# The shipped block itself, between its own markers. Empty extraction = the
# markers moved, which must fail loudly rather than test nothing.
block="$(awk '/^      # QUIESCE-THEN-START BLOCK/,/^      # END QUIESCE-THEN-START BLOCK/' "$watcher")"
case "$block" in
  *rank_start_room_ok* | *restore_normal_serving*) ;;
  *)
    echo "FAIL could not extract the quiesce-then-start block from $watcher" >&2
    exit 1
    ;;
esac

refusal_block="$(awk '/^      # REFUSAL RESTORE BLOCK/,/^      # END REFUSAL RESTORE BLOCK/' "$watcher")"
case "$refusal_block" in
  *rank_process_running*restore_normal_serving*) ;;
  *)
    echo "FAIL could not extract the refusal restore block from $watcher" >&2
    exit 1
    ;;
esac

fail=0
check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "  ok   $label -> $got"
  else
    echo "  FAIL $label -> got '$got', want '$want'"
    fail=1
  fi
}
contains() {
  local label="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) echo "  ok   $label" ;;
    *)
      echo "  FAIL $label -> '$needle' not in: $hay"
      fail=1
      ;;
  esac
}

quiesce_log="$tmp/quiesce-log"
restore_log="$tmp/restore-log"
quiesce_normal_serving() { echo ran >> "$quiesce_log"; }
restore_normal_serving() {
  echo ran >> "$restore_log"
  [ "${FAKE_RESTORE_OK:-1}" = 1 ]
}
launchctl() {
  [ "$1" = kickstart ] || return 0
  [ "${FAKE_KICKSTART_OK:-1}" = 1 ]
}

# Watcher-scope variables the block reads/writes at this point in a real tick.
# shellcheck disable=SC2034  # read by the extracted block, not by name here
uid=501
kicks=0
started_file="$tmp/started"
# shellcheck disable=SC2034
ready_file="$tmp/ready"
# shellcheck disable=SC2034
warm_file="$tmp/warm"
# shellcheck disable=SC2034
warm_fails_file="$tmp/warm-fails"
# shellcheck disable=SC2034
rank_log_offset_file="$tmp/rank-log-offset"
# shellcheck disable=SC2034
session_log_offset_file="$tmp/session-log-offset"
kicks_file="$tmp/kicks"
# shellcheck disable=SC2034
CLUSTER_RANK_LABEL="dev.mlx-cluster.rank"
# The edge the refusal branch triggers on: present = this watcher took
# standalone serving down and has not put it back.
quiesce_marker_file="$tmp/serving-quiesced"
# Real in the watcher (cluster-link-guards.sh), stubbed here so both the
# "a rank survived the refusal" and "nothing is running" cases are drivable.
rank_process_running() { [ "${FAKE_RANK_RUNNING:-0}" = 1 ]; }

reset() {
  rm -f "$quiesce_log" "$restore_log" "$started_file" "$kicks_file" "$quiesce_marker_file"
  export FAKE_ROOM_OK=1 FAKE_KICKSTART_OK=1 FAKE_RESTORE_OK=1 FAKE_RANK_RUNNING=0
  # shellcheck disable=SC2034
  kicks=0
}
tick() { out="$(eval "$block" 2>&1)"; }
refusal_tick() { out="$(eval "$refusal_block" 2>&1)"; }
marker() { [ -f "$quiesce_marker_file" ] && echo present || echo absent; }
restore_count() { [ -f "$restore_log" ] && wc -l < "$restore_log" | tr -d ' ' || echo 0; }

# rank_start_room_ok itself is real code pinned by test-mem-headroom.sh; here
# it is stubbed to drive both branches without a vm_stat fixture.
rank_start_room_ok() { [ "${FAKE_ROOM_OK:-1}" = 1 ]; }
# The real mem_headroom_ok sets this on refusal; the block only reads it for
# its own log line, so a fixed value under the stub is enough.
# shellcheck disable=SC2034
MEM_HEADROOM_DETAIL="not enough memory (stub)"

echo "room check refuses after quiesce: serving is restored:"
reset
export FAKE_ROOM_OK=0
tick
check "quiesce ran" 1 "$(wc -l < "$quiesce_log" | tr -d ' ')"
check "restore ran" 1 "$(restore_count)"
check "no attempt consumed" absent "$([ -f "$kicks_file" ] && cat "$kicks_file" || echo absent)"
contains "logs the restore" "standalone serving restored after the room check refused" "$out"

echo "   ...and a failed restore says so instead of pretending it worked:"
reset
export FAKE_ROOM_OK=0 FAKE_RESTORE_OK=0
tick
contains "logs the restore failure" "WARN failed to restore standalone serving after the room check refused" "$out"

echo "kickstart itself fails after quiesce: serving is restored:"
reset
export FAKE_KICKSTART_OK=0
tick
check "quiesce ran" 1 "$(wc -l < "$quiesce_log" | tr -d ' ')"
check "restore ran" 1 "$(restore_count)"
check "no attempt consumed" absent "$([ -f "$kicks_file" ] && cat "$kicks_file" || echo absent)"
contains "logs the restore" "standalone serving restored after the kickstart failure" "$out"

echo "a successful room check + kickstart does NOT restore (the rank serves next):"
reset
tick
check "quiesce ran" 1 "$(wc -l < "$quiesce_log" | tr -d ' ')"
check "restore did NOT run" 0 "$(restore_count)"
check "attempt consumed" 1 "$(cat "$kicks_file")"
check "marker left set for the refusal branch" present "$(marker)"

echo "a precondition refusal after that quiesce restores, once:"
reset
tick # quiesce + successful kickstart; marker now set, rank owns serving
export FAKE_RANK_RUNNING=1
refusal_tick
check "rank alive: restore did NOT run" 0 "$(restore_count)"
check "rank alive: marker still set" present "$(marker)"
contains "rank alive: says why" "a rank process is still running" "$out"
export FAKE_RANK_RUNNING=0
refusal_tick
check "rank gone: restore ran" 1 "$(restore_count)"
check "rank gone: marker cleared" absent "$(marker)"
contains "rank gone: logs the restore" "no rank survives; standalone serving restored" "$out"
refusal_tick
check "EDGE-TRIGGERED: the next refusal does not restore again" 1 "$(restore_count)"
contains "and says nothing was quiesced" "nothing to restore" "$out"

echo "   ...and a failed restore keeps the marker so the next tick retries:"
reset
tick
export FAKE_RESTORE_OK=0
refusal_tick
check "restore attempted" 1 "$(restore_count)"
check "marker still set" present "$(marker)"
contains "logs the restore failure" "after a quiesce and no rank survives; failed to restore" "$out"

echo "a refusal with no quiesce behind it restores nothing:"
reset
refusal_tick
check "restore did NOT run" 0 "$(restore_count)"
contains "says so" "nothing to restore" "$out"

# WHICH RUNG REFUSED REACHES THIS STREAM. Each rung of
# rank_start_preconditions_ok names itself on stderr, which the plist routes to
# a different file than these stdout summary lines — so without the token here
# the stdout log shows a refusal with no cause at all.
echo "the refusing rung's reason token reaches the refusal lines:"
for reason in peer-not-armed pd-debt-exhausted; do
  reset
  PRECONDITION_REASON="$reason"
  refusal_tick
  contains "no-quiesce branch names $reason" "(reason=$reason)" "$out"
  tick # quiesce + kickstart, so the next refusal takes the restore branch
  refusal_tick
  contains "post-quiesce branch names $reason" "(reason=$reason)" "$out"
done
unset PRECONDITION_REASON
# Unset is the state on any path that refused before the guard ran; it must not
# abort the block under `nounset`, and it must still say something.
reset
refusal_tick
contains "an unset reason degrades, not crashes" "(reason=unknown)" "$out"

exit "$fail"
