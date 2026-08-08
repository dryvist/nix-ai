#!/usr/bin/env bash
# THE CHECK THAT FAILS IF A LIFECYCLE COMMAND CAN LEAVE THE HOST WORSE THAN IT
# FOUND IT.
#
# Two 2026-08-08 defects, one shape: a command that takes something away and
# then exits without giving it back.
#
#   cluster-join  — quiesced standalone serving, failed to form a cluster, and
#                   exited. The watcher restores only on the up->down edge (an
#                   edge a healthy cable never produces) or from one of its own
#                   halt paths, so with no halt recorded nothing restored
#                   anything: 20+ minutes serving NOTHING, ended by an operator
#                   running cluster-restore by hand.
#   cluster-detach — SIGTERMed the rank process while the watcher, which is not
#                   told a detach is under way, kept converging and kickstarted
#                   ranks into the middle of the teardown. Three protection
#                   domains, 01:58Z.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL   — restore_serving_if_join_left_it_down is EXTRACTED FROM THE SHIPPED
#            cluster-join.sh (awk, by function name) and executed, so a drift in
#            the shipped branch logic fails here. restore_normal_serving,
#            rank_process_running/_absent and pd_debt_settle_counter are sourced
#            from their shipped layers and called as the commands call them.
#   STUB   — launchctl, as a fake on PATH recording every verb.
#   PIN    — the cluster-detach call sites and their ORDER, as source. detach
#            reaches macOS-only absolute paths (/bin/launchctl, /usr/sbin/sysctl)
#            that no PATH fake can intercept, so it is pinned the same way
#            tests/test-serving-restore.sh and tests/test-plugged-means-clustered.sh
#            already pin it rather than executed. Order is the property that
#            matters here: a bootout AFTER the signal closes no window at all.
#
# Usage:
#   BOOT_SCOPE=… RESTORE=… STATUS=… LEDGER=… RECORD=… SETTLE=… JOIN=… DETACH=… LAYERS=… \
#     bash test-teardown-recovery.sh
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# `#!/usr/bin/env bash` does not resolve in a Linux nix build sandbox; $BASH is
# the running interpreter's own absolute path (same fix as tests/test-peer-liveness.sh).
shebang="#!$BASH"

mkdir -p "$tmp/bin"
{
  printf '%s\n' "$shebang"
  cat << 'FAKE'
printf '%s\n' "$*" >> "$FAKE_DIR/launchctl.log"
case "${1:-}" in
  print) [ -f "$FAKE_DIR/loaded" ] ;;
  bootstrap)
    if [ "${FAKE_BOOTSTRAP_FAILS:-0}" = 1 ]; then
      exit 1
    fi
    touch "$FAKE_DIR/loaded"
    ;;
  *) exit 0 ;;
esac
FAKE
} > "$tmp/bin/launchctl"
chmod +x "$tmp/bin/launchctl"
PATH="$tmp/bin:$PATH"
export PATH
export FAKE_DIR="$tmp"

state_dir="$tmp/state"
mkdir -p "$state_dir"
halt_file="$state_dir/rank-halted"
kicks_file="$state_dir/rank-kickstarts"
debt_file="$state_dir/pd-debt"

export CLUSTER_ROLE=coordinator
export CLUSTER_SERVER_LABEL=dev.mlx.server
export CLUSTER_SERVER_PLIST="$tmp/server.plist"
export CLUSTER_WARMUP_LABEL=dev.mlx.warmup
export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'
export CLUSTER_PD_DEBT_MAX=5
export CLUSTER_PD_DEVICE_BUDGET=11
: > "$CLUSTER_SERVER_PLIST"

# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${LEDGER:?set LEDGER to cluster-pd-ledger.sh}"
# shellcheck disable=SC1090
source "${RECORD:?set RECORD to cluster-pd-record.sh}"
# shellcheck disable=SC1090
source "${SETTLE:?set SETTLE to cluster-pd-settle.sh}"
# shellcheck disable=SC1090
source "${STATUS:?set STATUS to cluster-rank-status.sh}"
# shellcheck disable=SC1090
source "${RESTORE:?set RESTORE to cluster-serving-restore.sh}"

join="${JOIN:?set JOIN to cluster-join.sh}"
detach="${DETACH:?set DETACH to cluster-detach.sh}"
layers="${LAYERS:?set LAYERS to cluster-script-layers.nix}"

# The shipped function itself, not a copy of it. Extracted by name so a rename
# fails loudly rather than silently testing nothing.
join_fn="$(awk '/^restore_serving_if_join_left_it_down\(\) \{/,/^\}/' "$join")"
if [ -z "$join_fn" ]; then
  echo "FAIL cluster-join.sh no longer defines restore_serving_if_join_left_it_down" >&2
  exit 1
fi
eval "$join_fn"

# pgrep seam, as a generated executable: the shipped code invokes it through a
# variable holding a path, so a shell function would not exercise the same call
# (same reasoning as tests/test-pd-debt.sh).
cat > "$tmp/bin/fake-pgrep" << PGREP
#!$BASH
exit "\$(cat '$tmp/pgrep-rc' 2>/dev/null || echo 1)"
PGREP
chmod +x "$tmp/bin/fake-pgrep"
export CLUSTER_PGREP_BIN="$tmp/bin/fake-pgrep"
rank_absent() { printf '1\n' > "$tmp/pgrep-rc"; }
rank_running() { printf '0\n' > "$tmp/pgrep-rc"; }

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
reset() {
  rm -f "$tmp/launchctl.log" "$tmp/loaded" "$halt_file" "$kicks_file" "$debt_file"
  export FAKE_BOOTSTRAP_FAILS=0
  rank_absent
}
warmed() { grep -qE 'kickstart .*dev\.mlx\.warmup' "$tmp/launchctl.log" 2> /dev/null && echo yes || echo no; }

echo "cluster-join's failure path restores standalone serving:"

reset
quiesced=false
out="$(restore_serving_if_join_left_it_down 2>&1)"
check "an early refusal restores nothing (serving was never taken away)" no "$(warmed)"
contains "and says so" "never quiesced" "$out"

reset
quiesced=true
out="$(restore_serving_if_join_left_it_down 2>&1)"
check "quiesced + no rank + no halt -> serving is restored" yes "$(warmed)"
contains "the branch that fired is named" "restoring standalone serving" "$out"
check "the booted-out server agent is bootstrapped back first" yes \
  "$(grep -qE 'bootstrap ' "$tmp/launchctl.log" 2> /dev/null && echo yes || echo no)"

reset
rank_running
quiesced=true
out="$(restore_serving_if_join_left_it_down 2>&1)"
check "a running rank means the watcher owns serving -> no restore" no "$(warmed)"
contains "and the deferral is logged, not silent" "rank process is running" "$out"

reset
quiesced=true
printf 'cause=peer-absent\tdetail\n' > "$halt_file"
out="$(restore_serving_if_join_left_it_down 2>&1)"
check "a recorded halt means the watcher's halt path restores -> no restore" no "$(warmed)"
contains "and the deferral names the halt" "halt is recorded" "$out"

# The failure the whole trap exists to make visible: a restore that could not
# run must SAY the host is serving nothing, never exit quiet.
reset
# shellcheck disable=SC2034  # read by the extracted shipped function
quiesced=true
export FAKE_BOOTSTRAP_FAILS=1
out="$(restore_serving_if_join_left_it_down 2>&1)"
contains "a failed restore is reported as serving nothing" "serving nothing" "$out"

echo
echo "cluster-join is WIRED to be able to restore (a function nobody can call fixes nothing):"

pin() {
  local label="$1" file="$2" pattern="$3" body
  # Comment-stripped before matching, and materialised first: under pipefail a
  # `grep -v … | grep -q` that matches early takes SIGPIPE on the producer and
  # reports a hit as a miss (GNU grep only — invisible on macOS).
  body="$(grep -v '^[[:space:]]*#' "$file")"
  if grep -Eq "$pattern" <<< "$body"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label -> no code line matching /$pattern/ in $file"
    fail=1
  fi
}

pin "the restore runs on EVERY exit after the quiesce, via a trap" "$join" \
  'trap restore_serving_if_join_left_it_down EXIT'
pin "the coordinator arms it before the first destructive verb" "$join" \
  'quiesced=true'
pin "join is given the single restore definition" "$layers" \
  'cluster-serving-restore\.sh'

echo
echo "cluster-detach unloads the rank JOB before signalling the process:"

bootout_line="$(grep -n 'launchctl bootout "gui/\$uid/\${CLUSTER_RANK_LABEL}"' "$detach" | head -n1 | cut -d: -f1)"
signal_line="$(grep -n 'launchctl kill SIGTERM' "$detach" | head -n1 | cut -d: -f1)"
if [ -n "$bootout_line" ] && [ -n "$signal_line" ] && [ "$bootout_line" -lt "$signal_line" ]; then
  echo "  ok   the rank job is booted out (line $bootout_line) before any signal (line $signal_line)"
else
  echo "  FAIL bootout (line ${bootout_line:-none}) must precede the first signal (line ${signal_line:-none}) — a later bootout closes no window"
  fail=1
fi

pin "and is bootstrapped back, or the next join could never start a rank" "$detach" \
  'launchctl bootstrap "gui/\$uid" "\$CLUSTER_RANK_PLIST"'
pin "a failed bootstrap-back is reported, never silent" "$detach" \
  'could not bootstrap .*back'
pin "the kickstart counter is SETTLED, not deleted" "$detach" \
  'pd_debt_settle_counter .* "\$state_dir/rank-kickstarts"'
pin "and billed to the halt latch's cause, not to this command's name" "$detach" \
  'rank-halt-latched'
pin "detach is given the counter-settle layer" "$layers" \
  'cluster-pd-settle\.sh'

# The release must run on EVERY exit, including one errexit takes before the end
# of the script: an abort after the bootout would otherwise leave the rank job
# unloaded, and nothing but a darwin-rebuild loads it again.
pin "the release runs on every exit, via a trap" "$detach" \
  'trap release_session EXIT'
pin "gated so an exit BEFORE the teardown settles nothing" "$detach" \
  'teardown_started'
# ...and ONLY via the trap. A mid-script call would clear rank-kickstarts before
# markers_clear is judged, satisfying that postcondition by deletion rather than
# by the watcher's teardown having actually run.
calls="$(grep -c 'release_session' <<< "$(grep -v '^[[:space:]]*#' "$detach")")"
check "release_session is defined and trapped, never called inline" 2 "$calls"

echo
echo "...and clearing that counter charges the ledger rather than laundering it:"

reset
printf '2\n' > "$kicks_file"
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 "cluster-detach" "test" 2> /dev/null
check "the counter is gone, so the next session starts whole" absent \
  "$([ -f "$kicks_file" ] && echo present || echo absent)"
check "and its outstanding attempts are on the boot-scoped ledger" 2 "$(pd_debt_count "$debt_file")"

reset
pd_debt_settle_counter "$debt_file" "$kicks_file" 0 "cluster-detach" "test" 2> /dev/null
check "an already-clear counter charges nothing (safe on every exit)" 0 "$(pd_debt_count "$debt_file")"

exit "$fail"
