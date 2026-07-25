#!/usr/bin/env bash
# Pins the two properties that made the RDMA PD guard useless in practice on
# 2026-07-25, both in modules/mlx/scripts/cluster-link-watcher.sh:
#
#   1. The guard cleared itself on a rank that was merely `state = running`.
#      mlx_lm.server reaches that state instantly and then sits in the jaccl
#      connect back-off (2s+4s+8s) before mx.distributed.init() throws errno 60
#      and it exits. A tick landing inside that window cleared the halt — so the
#      halt was cleared by the corpse of the attempt that tripped it, and the
#      watcher retried forever. Three complete halt -> clear -> 3x kickstart
#      cycles were observed back to back, each leaking another protection
#      domain. PD exhaustion is reboot-only, so a defeated guard is worse than
#      no guard: it spends the budget while reporting that it is protecting it.
#
#   2. The PD-guard halt did not restore standalone serving. Every attempt is
#      preceded by quiesce_normal_serving, and the only restore sat on the
#      up->down edge — an edge that never arrives when the local link is fine
#      and it is the PEER that cannot form the cluster. The worker served no
#      inference for over an hour with its own probe reading `up`.
#
# LIMITATION, stated plainly, same as tests/test-link-debounce.sh: this MIRRORS
# the watcher's logic rather than sourcing it, because the block is inline in a
# script that calls launchctl, sysctl and curl at import time. It proves the
# logic is right; it does NOT stop the watcher drifting from this copy.
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
started_file="$state_dir/rank-started"
kicks_file="$state_dir/rank-kickstarts"
halt_file="$state_dir/rank-halted"
halt_latch_file="$state_dir/rank-halt-latched"
restore_log="$state_dir/restores"
: > "$restore_log"

now=1000
restore_normal_serving() { printf 'restore\n' >> "$restore_log"; }
restores() { wc -l < "$restore_log" | tr -d ' '; }

# The guard-clear branch, mirrored. running=1 means launchd reports
# `state = running` this tick.
converge_tick() {
  local running="$1"
  [ "$running" -eq 1 ] || return 0
  [ -f "$started_file" ] || printf '%s\n' "$now" > "$started_file"
  local settled_at
  settled_at="$(cat "$started_file")"
  if [ "$settled_at" -gt 0 ] &&
    [ "$((now - settled_at))" -ge "${CLUSTER_RANK_SETTLE_SECS:-60}" ]; then
    rm -f "$kicks_file" "$halt_file" "$halt_latch_file"
  fi
}

# The kickstart/halt branch, mirrored.
kickstart_tick() {
  local kicks=0
  [ -f "$kicks_file" ] && kicks="$(cat "$kicks_file")"
  if [ "$kicks" -ge "${CLUSTER_MAX_KICKSTARTS:-3}" ]; then
    printf 'halted\n' > "$halt_file"
    printf 'latched\n' > "$halt_latch_file"
    restore_normal_serving
    return 0
  fi
  printf '%s\n' "$((kicks + 1))" > "$kicks_file"
  rm -f "$started_file"
}

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
halted() { [ -f "$halt_file" ] && echo yes || echo no; }

echo "a transiently-running rank must NOT clear the guard:"
CLUSTER_RANK_SETTLE_SECS=60
CLUSTER_MAX_KICKSTARTS=3
kickstart_tick # attempt 1
kickstart_tick # attempt 2
kickstart_tick # attempt 3
kickstart_tick # cap reached -> halt
check "three failed starts halt the guard" yes "$(halted)"
check "halting restores standalone serving" 1 "$(restores)"

# The rank comes up, lives 14s (the jaccl back-off), and dies. This is the exact
# shape that used to clear the halt.
now=$((now + 2))
converge_tick 1
now=$((now + 12))
converge_tick 1
check "a 14s-lived rank leaves the halt in place" yes "$(halted)"
check "and leaves the kickstart count intact" 3 "$(cat "$kicks_file")"

echo "a genuinely settled rank DOES clear the guard:"
now=$((now + 60))
converge_tick 1
check "past the settle window the halt clears" no "$(halted)"
check "kickstart count cleared too" "" "$(cat "$kicks_file" 2> /dev/null || echo '')"
check "latch cleared too" "" "$(cat "$halt_latch_file" 2> /dev/null || echo '')"

echo "settle window is configurable:"
rm -f "$started_file" "$halt_file" "$kicks_file" "$halt_latch_file"
CLUSTER_RANK_SETTLE_SECS=5
printf 'halted\n' > "$halt_file"
now=$((now + 1))
converge_tick 1
now=$((now + 2))
converge_tick 1
check "below the window the halt holds" yes "$(halted)"
now=$((now + 5))
converge_tick 1
check "at the window the halt clears" no "$(halted)"

echo "zero disables the settle requirement (documented escape hatch):"
rm -f "$started_file" "$halt_file"
CLUSTER_RANK_SETTLE_SECS=0
printf 'halted\n' > "$halt_file"
converge_tick 1
check "settle 0 clears immediately" no "$(halted)"

echo "the host never sits quiesced with nothing serving:"
# One restore per halt, and a halt always pairs with one — the property that
# was violated (halt with no restore) can never hold again.
: > "$restore_log"
rm -f "$halt_file" "$kicks_file" "$started_file" "$halt_latch_file"
CLUSTER_MAX_KICKSTARTS=2
kickstart_tick
kickstart_tick
kickstart_tick
check "halt reached" yes "$(halted)"
check "exactly one restore accompanied it" 1 "$(restores)"

exit "$fail"
