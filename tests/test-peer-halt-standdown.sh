#!/usr/bin/env bash
# THE CHECK THAT FAILS IF A WORKER KEEPS RUNNING INSIDE A GROUP ITS COORDINATOR
# HAS ABANDONED.
#
# Every teardown above the worker block — readiness, the health gate, the soak
# probe — is coordinator-gated, because only rank 0 binds the endpoint they
# probe. So a worker whose coordinator halts while the worker's own rank process
# and TCP session survive had no escalation at all: it waits inside a JACCL
# all-reduce its peer has already left, with every local signal green.
#
# This pins the worker-side detector: it reads the coordinator's own published
# peer state, strikes ONLY on a positive halted_cause, clears on a clean read,
# does NOT strike when the fetch fails (an unreachable peer is peer-liveness's
# verdict, not this one's), and at the strike cap runs the same standdown the
# rendezvous-absent path runs — halt first, SIGTERM (never SIGKILL), ceiling
# back, serving back, page.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — the WORKER PEER-HALT BLOCK is EXTRACTED FROM THE SHIPPED
#           cluster-link-watcher.sh between its own comment markers and
#           executed, so a drift in the shipped sequence fails here.
#   STUB  — peer_state_enabled, peer_state_fetch, halt_write,
#           restore_normal_serving, set_wired_limit, launchctl and alert are
#           stubbed to drive each branch deterministically; peer_state_fetch's
#           own behaviour is pinned by test-peer-armed-gate.sh.
#
# Usage:
#   WATCHER=… bash test-peer-halt-standdown.sh
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

watcher="${WATCHER:?set WATCHER to cluster-link-watcher.sh}"

# The shipped block itself, between its own markers. Empty extraction = the
# markers moved, which must fail loudly rather than test nothing.
block="$(awk '/^    # WORKER PEER-HALT BLOCK/,/^    # END WORKER PEER-HALT BLOCK/' "$watcher")"
case "$block" in
  *peer_state_fetch*halted_cause*halt_write*) ;;
  *)
    echo "FAIL could not extract the worker peer-halt block from $watcher" >&2
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

restore_log="$tmp/restore-log"
signal_log="$tmp/signal-log"
alert_log="$tmp/alert-log"
peer_state_enabled() { :; }
# The canned document the coordinator would be publishing. FAKE_FETCH_OK=0 is
# the unreadable-peer case, which must NOT count as a strike.
peer_state_fetch() {
  PEER_STATE_RAW=""
  [ "${FAKE_FETCH_OK:-1}" = 1 ] || return 1
  # shellcheck disable=SC2034  # read by the extracted block, not by name here
  PEER_STATE_RAW="{\"armed\":false,\"halted_cause\":${FAKE_CAUSE:-null},\"boot\":1,\"wired_ok\":true,\"generation\":\"g\",\"ts\":1}"
  return 0
}
halt_write() { printf 'cause=%s\n' "$3" > "$1"; }
restore_normal_serving() { echo ran >> "$restore_log"; }
set_wired_limit() { :; }
launchctl() { printf '%s %s\n' "$1" "${2:-}" >> "$signal_log"; }
alert() { printf '%s\n' "$1" >> "$alert_log"; }
hostname() { echo test-host; }

# Watcher-scope variables the block reads/writes at this point in a real tick.
# shellcheck disable=SC2034  # read by the extracted block, not by name here
uid=501
CLUSTER_ROLE=worker
# shellcheck disable=SC2034
CLUSTER_RANK_LABEL="dev.mlx-cluster.rank"
# shellcheck disable=SC2034
CLUSTER_WIRED_LIMIT_MB=102400
# shellcheck disable=SC2034
CLUSTER_PEER_HALT_STRIKES=2
started_file="$tmp/started"
halt_file="$tmp/halted"
# shellcheck disable=SC2034
halt_latch_file="$tmp/halt-latch"
# shellcheck disable=SC2034
ready_file="$tmp/ready"
# shellcheck disable=SC2034
warm_file="$tmp/warm"
peer_halt_strikes_file="$tmp/peer-halt-strikes"
peer_halt_check_file="$tmp/peer-halt-last-check"

# CLUSTER_STAT_BIN seam: the shipped block reads BSD `stat -f %m`, which does
# not exist in the Linux Nix sandbox this test also runs in under `nix flake
# check`. Falls back to GNU coreutils' `stat -c %Y` there.
stat_stub() {
  /usr/bin/stat -f %m "$3" 2> /dev/null || stat -c %Y "$3" 2> /dev/null
}
# shellcheck disable=SC2034
CLUSTER_STAT_BIN=stat_stub

reset() {
  rm -f "$restore_log" "$signal_log" "$alert_log" "$halt_file" \
    "$peer_halt_strikes_file" "$peer_halt_check_file"
  # Settled long ago, so the settle window and the check cadence are both open
  # regardless of wall-clock skew.
  touch "$started_file"
  touch -t 202001010000 "$started_file"
  export FAKE_FETCH_OK=1 FAKE_CAUSE=null
}
# Each tick must look like a fresh cadence window; the block touches its own
# check marker, so age it back out between ticks.
tick() {
  [ -f "$peer_halt_check_file" ] && touch -t 202001010000 "$peer_halt_check_file"
  out="$(eval "$block" 2>&1)"
}
strikes() { cat "$peer_halt_strikes_file" 2> /dev/null || echo absent; }
halted() { cat "$halt_file" 2> /dev/null || echo absent; }

echo "peer reports no halt: no strike, nothing torn down:"
reset
tick
check "no strikes" absent "$(strikes)"
check "not halted" absent "$(halted)"
contains "logs the clean read" "peer reports no halt" "$out"

echo "peer state unreadable: NO strike (that verdict belongs to peer-liveness):"
reset
export FAKE_FETCH_OK=0
tick
tick
check "still no strikes" absent "$(strikes)"
check "not halted" absent "$(halted)"
contains "says why it did not strike" "NO strike" "$out"

echo "peer reports halted: strikes accumulate, standdown only at the cap:"
reset
export FAKE_CAUSE='"pd-debt-exhausted"'
tick
check "one strike" 1 "$(strikes)"
check "not halted yet" absent "$(halted)"
contains "logs the strike" "peer HALTED (pd-debt-exhausted) while this rank is settled (1/2)" "$out"
tick
check "halted at the cap" cause=peer-halted "$(halted)"
check "strike counter cleared by the teardown" absent "$(strikes)"
check "restore ran" 1 "$([ -f "$restore_log" ] && wc -l < "$restore_log" | tr -d ' ' || echo 0)"
check "SIGTERM, never SIGKILL" "kill SIGTERM" "$(cat "$signal_log")"
contains "pages" "peer reported itself halted (pd-debt-exhausted)" "$(cat "$alert_log")"

echo "a clean read between strikes clears the count:"
reset
export FAKE_CAUSE='"peer-absent"'
tick
check "one strike" 1 "$(strikes)"
export FAKE_CAUSE=null
tick
check "cleared" absent "$(strikes)"
export FAKE_CAUSE='"peer-absent"'
tick
check "counting starts over" 1 "$(strikes)"
check "not halted" absent "$(halted)"

echo "a coordinator never runs this block:"
reset
export FAKE_CAUSE='"pd-debt-exhausted"'
# shellcheck disable=SC2034  # read by the extracted block, not by name here
CLUSTER_ROLE=coordinator
tick
tick
check "no strikes" absent "$(strikes)"
check "not halted" absent "$(halted)"

exit "$fail"
