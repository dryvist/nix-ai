#!/usr/bin/env bash
# THE CHECK THAT FAILS IF A BUSY-BUT-HEALTHY RANK GETS DECLARED WEDGED.
#
# The soak probe (health_gate_soak_probe) used to trust only endpoint_busy — an
# ESTABLISHED TCP connection on the endpoint port — as evidence the pipeline was
# busy rather than dead. That misses the case where the client that triggered
# real work (a generation, a model load) disconnects on its own timeout: the
# connection vanishes while the backend is still occupied, the soak probe's own
# request queues behind it, times out, and a healthy-but-busy rank is torn down
# as "wedged" (2026-08-16: a burst of requests against unloaded models did
# exactly this and halted a rank that was never broken).
#
# This pins that real generation progress (new_progress_lines — the SAME
# predicate cluster-peer-liveness.sh's coordinator_tick already checks first)
# is consulted BEFORE endpoint_busy, and that any progress since the last tick
# short-circuits the probe entirely rather than risking it against a still-busy
# backend.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — the SOAK BLOCK is EXTRACTED FROM THE SHIPPED cluster-link-watcher.sh
#           between its own comment markers and executed, so a drift in the
#           shipped sequence fails here.
#   STUB  — new_progress_lines, endpoint_busy, health_gate_soak_probe,
#           halt_write, restore_normal_serving, launchctl and alert are stubbed
#           to drive each branch deterministically; each one's own behaviour is
#           pinned by its own test file (test-mem-headroom.sh,
#           test-quiesce-restore.sh).
#
# Usage:
#   WATCHER=… bash test-soak-busy-vs-wedged.sh
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

watcher="${WATCHER:?set WATCHER to cluster-link-watcher.sh}"

# The shipped block itself, between its own markers. Empty extraction = the
# markers moved, which must fail loudly rather than test nothing.
block="$(awk '/^    # SOAK BLOCK/,/^    # END SOAK BLOCK/' "$watcher")"
case "$block" in
  *new_progress_lines* | *endpoint_busy* | *health_gate_soak_probe*) ;;
  *)
    echo "FAIL could not extract the soak block from $watcher" >&2
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

probe_log="$tmp/probe-log"
restore_log="$tmp/restore-log"
halt_log="$tmp/halt-log"
new_progress_lines() { printf '%s' "${FAKE_PROGRESS:-0}"; }
endpoint_busy() { [ "${FAKE_BUSY:-0}" = 1 ]; }
health_gate_soak_probe() {
  echo ran >> "$probe_log"
  [ "${FAKE_PROBE_OK:-1}" = 1 ]
}
restore_normal_serving() { echo ran >> "$restore_log"; }
halt_write() {
  echo "$3" >> "$halt_log"
  printf '%s\n' "$3" > "$1"
}
launchctl() { :; }
set_wired_limit() { :; }
alert() { :; }

# Watcher-scope variables the block reads/writes at this point in a real tick.
# shellcheck disable=SC2034  # read by the extracted block, not by name here
uid=501
# shellcheck disable=SC2034  # read by the extracted block, not by name here
CLUSTER_ROLE=coordinator
# shellcheck disable=SC2034
CLUSTER_RANK_LABEL="dev.mlx-cluster.rank"
# shellcheck disable=SC2034
CLUSTER_RANK_URL="http://127.0.0.1:11440"
# shellcheck disable=SC2034
CLUSTER_MODEL="test-model"
# shellcheck disable=SC2034
CLUSTER_RANK_PROGRESS_LOG="$tmp/rank.log"
warm_file="$tmp/warm"
# shellcheck disable=SC2034
health_gate_file="$tmp/health-gate"
halt_file="$tmp/halted"
# shellcheck disable=SC2034
halt_latch_file="$tmp/halt-latch"
soak_busy_skips_file="$tmp/soak-skips"
touch "$warm_file"
# Old enough to trip the recheck unconditionally, regardless of wall-clock skew.
touch -t 202001010000 "$warm_file"

reset() {
  rm -f "$probe_log" "$restore_log" "$halt_log" "$halt_file" "$soak_busy_skips_file"
  touch "$warm_file"
  touch -t 202001010000 "$warm_file"
  export FAKE_PROGRESS=0 FAKE_BUSY=0 FAKE_PROBE_OK=1
}
tick() { out="$(eval "$block" 2>&1)"; }
probe_count() { [ -f "$probe_log" ] && wc -l < "$probe_log" | tr -d ' ' || echo 0; }

echo "real generation progress: no probe fired, not declared wedged:"
reset
export FAKE_PROGRESS=3 FAKE_BUSY=0
tick
check "probe NOT called" 0 "$(probe_count)"
check "not halted" absent "$([ -f "$halt_file" ] && echo present || echo absent)"
contains "logs proof of life" "real traffic is live, treating as proof of life" "$out"

echo "progress AND endpoint_busy both true: progress still wins, no probe:"
reset
export FAKE_PROGRESS=1 FAKE_BUSY=1
tick
check "probe NOT called" 0 "$(probe_count)"

echo "no progress, endpoint busy: deferred exactly as before (unchanged behaviour):"
reset
export FAKE_PROGRESS=0 FAKE_BUSY=1
tick
check "probe NOT called" 0 "$(probe_count)"
contains "logs the defer" "busy pipeline is live" "$out"

echo "no progress, not busy, probe fails: still declared wedged (unchanged behaviour):"
reset
export FAKE_PROGRESS=0 FAKE_BUSY=0 FAKE_PROBE_OK=0
tick
check "probe called" 1 "$(probe_count)"
check "halted" health-gate-soak-fail "$(cat "$halt_file" 2> /dev/null || echo absent)"
check "restore ran" 1 "$([ -f "$restore_log" ] && wc -l < "$restore_log" | tr -d ' ' || echo 0)"

exit "$fail"
