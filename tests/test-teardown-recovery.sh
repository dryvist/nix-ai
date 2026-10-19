#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state" "$tmp/home/Library/LaunchAgents"

real_mv="$(command -v mv)"
write_stub() {
  printf '#!%s\n' "$BASH" > "$1"
  cat >> "$1"
}

write_stub "$tmp/bin/launchctl" <<'LAUNCHCTL'
printf 'launchctl %s\n' "$*" >> "$EVENTS"
if [ "${1:-}" = kill ] && [ "${2:-}" = SIGKILL ]; then touch "$SIGKILL_MARKER"; fi
if [ "${1:-}" = print ] && [ "${2##*/}" = "${FAKE_UNLOADED_LABEL:-}" ]; then exit 113; fi
LAUNCHCTL
write_stub "$tmp/bin/curl" <<'CURL'
case " $* " in
  *' -X POST '*) printf '{"usage":{"completion_tokens":1}}' ;;
esac
CURL
write_stub "$tmp/bin/ssh" <<'SSH'
printf 'ssh %s\n' "$*" >> "$EVENTS"
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
if [ "${FAKE_SSH_HANG:-false}" = true ]; then exec sleep 60; fi
exit "${FAKE_SSH_RC:-0}"
SSH
write_stub "$tmp/bin/sysctl" <<'SYSCTL'
case "${1:-}" in
  -n)
    case "${2:-}" in
      *swapusage*) printf 'vm.swapusage: total = 0M used = 0M free = 1M\n' ;;
      iogpu.wired_limit_mb) cat "$FAKE_WIRED_FILE" ;;
      kern.boottime) printf '{ sec = 100, usec = 0 }\n' ;;
      *) exit 1 ;;
    esac
    ;;
  -w)
    printf '%s\n' "${2#iogpu.wired_limit_mb=}" > "$FAKE_WIRED_FILE"
    ;;
  *) printf '0\n' ;;
esac
SYSCTL
write_stub "$tmp/bin/sw-vers" <<'SWVERS'
exit 0
SWVERS
write_stub "$tmp/bin/darwin-version" <<'DARWINVERSION'
exit 1
DARWINVERSION
write_stub "$tmp/bin/stat" <<'STAT'
printf '%s\n' "$FAKE_MTIME"
STAT
write_stub "$tmp/bin/sed" <<'SED'
while IFS= read -r line; do
  if [[ "$line" =~ ^\{[[:space:]]*sec[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$line" == *'used = '* ]]; then
    value="${line#*used = }"
    printf '%s\n' "${value%%M*}"
  fi
done
SED
chmod +x "$tmp/bin/launchctl" "$tmp/bin/curl" "$tmp/bin/ssh" "$tmp/bin/sysctl"
chmod +x "$tmp/bin/sw-vers" "$tmp/bin/darwin-version" "$tmp/bin/stat" "$tmp/bin/sed"
write_stub "$tmp/bin/sudo" <<'SUDO'
[ "${1:-}" = -n ] && shift
"$@"
SUDO
chmod +x "$tmp/bin/sudo"

source modules/mlx/scripts/cluster-teardown.sh
source modules/mlx/scripts/cluster-detach.sh
source modules/mlx/scripts/cluster-boot-scope.sh
source modules/mlx/scripts/cluster-peer-state-write.sh
source modules/mlx/scripts/cluster-rank-status.sh
source modules/mlx/scripts/cluster-rank-reap.sh

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
    *) echo "  FAIL $label -> '$needle' missing from '$hay'"; fail=1 ;;
  esac
}

export PATH="$tmp/bin:$PATH"
export EVENTS="$tmp/events"
export HOME="$tmp/home"
export CLUSTER_STATE_DIR="$tmp/state"
export CLUSTER_STATE_FILE="$tmp/state/link-state"
export CLUSTER_PEER_STATE_FILE="$tmp/state/peer-state.json"
export CLUSTER_LAUNCH_AGENTS_DIR="$tmp/home/Library/LaunchAgents"
export CLUSTER_LAUNCHCTL_BIN="$tmp/bin/launchctl"
export CLUSTER_SYSCTL_BIN="$tmp/bin/sysctl"
export CLUSTER_SED_BIN="$tmp/bin/sed"
export CLUSTER_STAT_BIN="$tmp/bin/stat"
export CLUSTER_SUDO_BIN="$tmp/bin/sudo"
export CLUSTER_SW_VERS_BIN="$tmp/bin/sw-vers"
export CLUSTER_DARWIN_VERSION_BIN="$tmp/bin/darwin-version"
export TEST_MV_BIN="$real_mv"
export FAKE_WIRED_FILE="$tmp/wired-limit"
printf '0\n' > "$FAKE_WIRED_FILE"
export CLUSTER_LIFECYCLE_LOG="$tmp/lifecycle.log"
export FAKE_SSH_LOG="$tmp/ssh.log"
export CLUSTER_SSH_BIN="$tmp/bin/ssh"
export CLUSTER_ROLE=worker
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_STANDALONE_WIRED_LIMIT_MB=0
export CLUSTER_RANK_LABEL=dev.test.rank
export CLUSTER_RANK_PROCESS_PATTERN=/fake-rank
export CLUSTER_DETACH_TIMEOUT_SECS=0
export CLUSTER_STANDALONE_PROBES='dev.test.server http://127.0.0.1:1 test'
export CLUSTER_DETACH_SWAP_THRESHOLD_MB=20000
export CLUSTER_PEER_STATE_FILE="$tmp/state/peer-state.json"
export CLUSTER_SOFTWARE_JSON='{"nix_ai":"a","mlx":"c","mlx_lm":"d","macos":"e"}'
export CLUSTER_IOCLASSCOUNT_BIN="$tmp/bin/ioclasscount"
write_stub "$CLUSTER_IOCLASSCOUNT_BIN" <<'IOCLASS'
printf '%s = 0\n' "$1"
IOCLASS
chmod +x "$CLUSTER_IOCLASSCOUNT_BIN"
export CLUSTER_PGREP_BIN="$tmp/bin/pgrep"
write_stub "$CLUSTER_PGREP_BIN" <<'PGREP'
[ -f "$SIGKILL_MARKER" ] && exit 1
[ "${FAKE_PGREP_STATE:-absent}" = running ] || exit 1
printf '123\n'
PGREP
export CLUSTER_KILL_BIN="$tmp/bin/kill"
write_stub "$CLUSTER_KILL_BIN" <<'KILL'
exit 0
KILL
export CLUSTER_PKILL_BIN="$tmp/bin/pkill"
write_stub "$CLUSTER_PKILL_BIN" <<'PKILL'
exit 0
PKILL
chmod +x "$CLUSTER_PGREP_BIN" "$CLUSTER_KILL_BIN" "$CLUSTER_PKILL_BIN"
write_stub "$tmp/bin/mv" <<'MV'
last="${@: -1}"
if [ "${FAIL_PEER_WRITE:-false}" = true ] && [ "$last" = "$CLUSTER_PEER_STATE_FILE" ]; then
  exit 1
fi
exec "$TEST_MV_BIN" "$@"
MV
chmod +x "$tmp/bin/mv"

: > "$EVENTS"
mkdir -p "$tmp/Some App.app"
printf 'label-a\nlabel-b\nlabel-c %s\n' "$tmp/Some App.app/label-c.plist" > "$tmp/state/quiesced-agents"
touch "$tmp/home/Library/LaunchAgents/label-a.plist" "$tmp/Some App.app/label-c.plist"
peer_state_write() { printf 'disarm\n' >> "$EVENTS"; }
rank_process_absent_calls=0
rank_process_absent() {
  rank_process_absent_calls=$((rank_process_absent_calls + 1))
  [ "$rank_process_absent_calls" -gt 1 ]
}
rank_stop_verified() { printf 'stop\n' >> "$EVENTS"; return 0; }
pd_held_count() { printf 'count\n' >> "$EVENTS"; PD_HELD=0; return 0; }
set_wired_limit() { printf 'ceiling\n' >> "$EVENTS"; return 0; }
restore_normal_serving() { printf 'restore-serving\n' >> "$EVENTS"; return 0; }
link_state_write() { printf '%s\n' "$1" > "$CLUSTER_STATE_FILE"; printf 'link-%s\n' "$1" >> "$EVENTS"; }

rank_process_absent_calls=0
rank_process_absent || true
rank_process_absent_calls=0
rank_stop_verified
pd_held_count
check 'PD count fixture reports zero' 0 "$PD_HELD"
: > "$EVENTS"

if cluster_teardown > "$tmp/teardown.log" 2>&1; then
  check 'normal teardown returns success' 0 "$?"
else
  echo '  FAIL normal teardown returned failure'; fail=1
fi
ordered="$(tr '\n' ' ' < "$EVENTS")"
contains 'teardown order' 'disarm stop count ceiling restore-serving launchctl bootstrap gui/'"$(id -u)"' '"$tmp/home/Library/LaunchAgents/label-a.plist"' launchctl kickstart gui/'"$(id -u)"'/label-b launchctl bootstrap gui/'"$(id -u)"' '"$tmp/Some App.app/label-c.plist"' link-down' "$ordered"
check 'quiesced label file truncated' 0 "$(wc -c < "$tmp/state/quiesced-agents" | tr -d ' ')"
check 'link state down after teardown' down "$(cat "$CLUSTER_STATE_FILE")"

: > "$EVENTS"
printf 'up\n' > "$CLUSTER_STATE_FILE"
rank_process_absent() { return 1; }
rank_stop_verified() { printf 'stop-survivor\n' >> "$EVENTS"; return 1; }
if rank_process_absent; then
  echo '  FAIL survivor fixture reported the rank absent'; fail=1
fi
if rank_stop_verified; then
  echo '  FAIL survivor stop fixture reported success'; fail=1
fi
: > "$EVENTS"
if cluster_teardown > "$tmp/survivor.log" 2>&1; then
  echo '  FAIL surviving rank teardown returned success'; fail=1
fi
survivor_events="$(cat "$EVENTS")"
check 'surviving rank leaves state up' up "$(cat "$CLUSTER_STATE_FILE")"
check 'surviving rank stops before count/restore' 'disarm
stop-survivor' "$survivor_events"

unset -f rank_process_absent rank_process_pids rank_reap_verified rank_stop_verified
source modules/mlx/scripts/cluster-rank-status.sh
source modules/mlx/scripts/cluster-rank-reap.sh
SIGKILL_MARKER="$tmp/sigkill.marker"
export SIGKILL_MARKER
export FAKE_PGREP_STATE=running
sleep() {
  command sleep 0.01
  SECONDS=$((SECONDS + ${1:-1}))
}
if rank_stop_verified; then
  check 'rank_stop_verified completes after fake SIGKILL' 0 "$?"
else
  echo '  FAIL fake SIGKILL did not prove rank absence'; fail=1
fi
check 'SIGKILL sets the reboot-required flag' 1 "$TEARDOWN_REBOOT"
set +e
(cluster_detach_finish 0 0 "$TEARDOWN_REBOOT" false)
detach_rc=$?
set -e
check 'SIGKILL teardown exits with reboot code' 3 "$detach_rc"
set +e
(cluster_detach_finish 1 0 "$TEARDOWN_REBOOT" false)
detach_rc=$?
set -e
check 'SIGKILL reboot status survives a teardown failure' 3 "$detach_rc"
set +e
(cluster_detach_finish 0 0 0 true)
detach_rc=$?
set -e
check 'stale swap exits with reboot code' 3 "$detach_rc"

echo 'coordinator maps worker detach results to the documented exit contract:'
: > "$EVENTS"
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
export CLUSTER_ROLE=coordinator
export CLUSTER_PEER_SSH=user@worker
export CLUSTER_STANDALONE_PROBES='dev.test.server http://127.0.0.1:1 test'
export CLUSTER_DETACH_SWAP_THRESHOLD_MB=20000
export CLUSTER_DETACH_TIMEOUT_SECS=10
cluster_teardown() { printf 'local-teardown\n' >> "$EVENTS"; TEARDOWN_REBOOT=0; return 0; }
cluster_lifecycle_log_start() { exec > "$CLUSTER_LIFECYCLE_LOG" 2>&1; }
for pair in '42 1' '255 1' '3 3'; do
  read -r FAKE_SSH_RC expected_rc <<< "$pair"
  export FAKE_SSH_RC
  : > "$EVENTS"
  : > "$FAKE_SSH_LOG"
  : > "$CLUSTER_LIFECYCLE_LOG"
  set +e
  (cluster_detach_main)
  detach_rc=$?
  set -e
  check "worker detach rc=$FAKE_SSH_RC maps to coordinator rc=$expected_rc" "$expected_rc" "$detach_rc"
  check 'coordinator issued one worker detach' 1 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"
  check 'worker detach arguments' '-o BatchMode=yes -o ConnectTimeout=10 user@worker cluster-detach --worker' "$(cat "$FAKE_SSH_LOG")"
  contains 'peer failure reason and raw rc are logged' \
    "REFUSE reason=peer-detach-failed detail=worker detach failed (rc=$FAKE_SSH_RC)" "$(cat "$CLUSTER_LIFECYCLE_LOG")"
done

echo 'coordinator detach applies the detach timeout plus a 30s SSH deadline:'
export FAKE_SSH_HANG=true
export FAKE_SSH_RC=0
export CLUSTER_DETACH_TIMEOUT_SECS=1
export CLUSTER_STANDALONE_PROBES=
: > "$EVENTS"
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
SECONDS=0
set +e
(
  cluster_detach_main
) > "$tmp/detach-timeout.log" 2>&1
detach_rc=$?
set -e
check 'stalled peer detach exits nonzero' 1 "$detach_rc"
contains 'peer detach timeout has a stable reason' 'REFUSE reason=peer-detach-timeout' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
contains 'peer detach deadline includes 30s reap margin' 'worker ssh exceeded the 31s deadline' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
unset FAKE_SSH_HANG
export CLUSTER_STANDALONE_PROBES='dev.test.server http://127.0.0.1:1 test'
export CLUSTER_DETACH_TIMEOUT_SECS=10

first_local="$(grep -n '^local-teardown$' "$EVENTS" | cut -d: -f1)"
first_ssh="$(grep -n '^ssh ' "$EVENTS" | cut -d: -f1)"
check 'local teardown precedes remote detach' yes "$([ "$first_local" -lt "$first_ssh" ] && echo yes || echo no)"

: > "$EVENTS"
: > "$FAKE_SSH_LOG"
export CLUSTER_ROLE=worker
set +e
(cluster_detach_main)
detach_rc=$?
set -e
check 'worker detach succeeds without initiating ssh' 0 "$detach_rc"
check 'worker issued no ssh' 0 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"

echo 'detach probes only the resident servers loaded on this host:'
export FAKE_UNLOADED_LABEL=dev.test.unloaded
export CLUSTER_STANDALONE_PROBES='dev.test.unloaded http://127.0.0.1:2 other
dev.test.server http://127.0.0.1:1 test'
: > "$CLUSTER_LIFECYCLE_LOG"
set +e
(cluster_detach_main)
detach_rc=$?
set -e
check 'detach with one loaded resident succeeds' 0 "$detach_rc"
contains 'unloaded resident is skipped' 'dev.test.unloaded not loaded; not probed' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
contains 'loaded resident is probed' 'dev.test.server returned a real completion' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
export CLUSTER_STANDALONE_PROBES='dev.test.unloaded http://127.0.0.1:2 other'
: > "$CLUSTER_LIFECYCLE_LOG"
set +e
(cluster_detach_main)
detach_rc=$?
set -e
check 'detach with no loaded resident succeeds' 0 "$detach_rc"
contains 'no loaded resident is reported' 'serving    : no resident loaded' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
export CLUSTER_STANDALONE_PROBES='dev.test.server http://127.0.0.1:1 test'
export CLUSTER_DETACH_TIMEOUT_SECS=0
: > "$CLUSTER_LIFECYCLE_LOG"
set +e
(cluster_detach_main)
detach_rc=$?
set -e
check 'loaded resident without a completion fails detach' 1 "$detach_rc"
contains 'missing completion has a stable reason' 'REFUSE reason=serving-not-restored' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
unset FAKE_UNLOADED_LABEL
export CLUSTER_DETACH_TIMEOUT_SECS=10

echo 'lifecycle lock record keeps the first owner and fresh acquisition:'
lock="$CLUSTER_STATE_DIR/cluster-lifecycle.lock"
rm -rf "$lock"
mkdir -p "$lock"
printf '%s\n' "$$" > "$lock/pid"
printf '100\n' > "$lock/boot"
if cluster_lifecycle_lock_record "$lock" > "$tmp/late-lock-record.log" 2>&1; then
  late_lock_record_rc=0
else
  late_lock_record_rc=$?
fi
if [ "$late_lock_record_rc" -eq 1 ] &&
  [ "$(cat "$lock/pid")" = "$$" ] && [ "$(cat "$lock/boot")" = 100 ]; then
  echo '  ok   late lock writer returns 1 and preserves live pid and boot records'
else
  echo '  FAIL late lock writer did not return 1 with unchanged records'; fail=1
fi
rm -rf "$lock"
if cluster_lifecycle_lock_acquire; then
  if [ "$(cat "$lock/pid")" = "$BASHPID" ] && [ "$(cat "$lock/boot")" = 100 ]; then
    echo '  ok   fresh lifecycle lock records caller pid and boot'
  else
    echo '  FAIL fresh lifecycle lock records were incorrect'; fail=1
  fi
  cluster_lifecycle_lock_release
else
  echo '  FAIL fresh lifecycle lock acquisition failed'; fail=1
fi

echo 'detach refuses while a join owns the lifecycle lock:'
cluster_lifecycle_lock_acquire
: > "$EVENTS"
: > "$CLUSTER_LIFECYCLE_LOG"
set +e
(cluster_detach_main --worker) > /dev/null 2>&1
detach_rc=$?
set -e
check 'overlapping detach exits nonzero' 1 "$detach_rc"
contains 'overlapping detach is logged' 'REFUSE reason=lifecycle-locked' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
check 'overlapping detach does not teardown' 0 "$(wc -l < "$EVENTS" | tr -d ' ')"
cluster_lifecycle_lock_release

echo 'session-scoped worker cleanup refuses a newer lifecycle session:'
printf '{"session":"20261018T120000Z-ffffffff"}\n' > "$CLUSTER_PEER_STATE_FILE"
: > "$EVENTS"
: > "$CLUSTER_LIFECYCLE_LOG"
set +e
(cluster_detach_main --worker --session 20261018T120000Z-0123abcd) > /dev/null 2>&1
detach_rc=$?
set -e
check 'mismatched worker cleanup exits nonzero' 1 "$detach_rc"
contains 'mismatched worker cleanup is logged' 'REFUSE reason=peer-session-mismatch' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
check 'mismatched worker cleanup does not teardown' 0 "$(wc -l < "$EVENTS" | tr -d ' ')"

echo 'a peer disarm write failure leaves link-state up and fails teardown and detach:'
unset -f peer_state_write rank_process_absent rank_process_pids rank_stop_verified pd_held_count \
  set_wired_limit restore_normal_serving link_state_write cluster_teardown cluster_lifecycle_log_start
source modules/mlx/scripts/cluster-peer-state-write.sh
source modules/mlx/scripts/cluster-pd-count.sh
source modules/mlx/scripts/cluster-wired-limit.sh
source modules/mlx/scripts/cluster-serving-restore.sh
source modules/mlx/scripts/cluster-rank-status.sh
source modules/mlx/scripts/cluster-rank-reap.sh
source modules/mlx/scripts/cluster-teardown.sh
export CLUSTER_STATE_FILE="$tmp/state/link-state"
export CLUSTER_PEER_STATE_FILE="$tmp/state/peer-state.json"
export CLUSTER_STATE_DIR="$tmp/state"
export CLUSTER_LIFECYCLE_COMPONENT=cluster-teardown
export CLUSTER_RANK_PROCESS_PATTERN=/fake-rank
export CLUSTER_IOCLASSCOUNT_BIN="$tmp/bin/ioclasscount"
export CLUSTER_STANDALONE_WIRED_LIMIT_MB=1000
printf '2000\n' > "$FAKE_WIRED_FILE"
printf 'up\n' > "$CLUSTER_STATE_FILE"
export FAIL_PEER_WRITE=true
: > "$CLUSTER_LIFECYCLE_LOG"
if cluster_teardown > "$tmp/disarm-failure.log" 2>&1; then
  echo '  FAIL disarm failure returned success'; fail=1
else
  check 'disarm failure returns nonzero' 1 "$?"
fi
check 'failed disarm leaves link-state up' up "$(cat "$CLUSTER_STATE_FILE")"
check 'failed disarm still restores wired ceiling' 1000 "$(cat "$FAKE_WIRED_FILE")"
contains 'failed disarm has a stable refusal token' 'REFUSE reason=disarm-failed' "$(cat "$tmp/disarm-failure.log")"

export CLUSTER_ROLE=worker
export CLUSTER_STANDALONE_PROBES=
export CLUSTER_DETACH_TIMEOUT_SECS=0
: > "$CLUSTER_LIFECYCLE_LOG"
set +e
(cluster_detach_main) > /dev/null 2>&1
detach_rc=$?
set -e
check 'detach reports disarm failure' 1 "$detach_rc"
check 'detach keeps link-state up after disarm failure' up "$(cat "$CLUSTER_STATE_FILE")"
contains 'detach reports disarm failure' 'REFUSE reason=disarm-failed' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
unset FAIL_PEER_WRITE

echo 'teardown waits for PD release before it requests a reboot:'
rank_process_absent() { return 0; }
rank_stop_verified() { return 0; }
peer_state_write() { return 0; }
set_wired_limit() { return 0; }
restore_normal_serving() { return 0; }
link_state_write() { :; }
sleep() { printf 'sleep\n' >> "$EVENTS"; }
pd_reads=0
FAKE_PD_SEQUENCE=
pd_held_count() {
  local -a seq=()
  local idx
  read -r -a seq <<< "$FAKE_PD_SEQUENCE"
  idx=$pd_reads
  if [ "$idx" -ge "${#seq[@]}" ]; then idx=$((${#seq[@]} - 1)); fi
  pd_reads=$((pd_reads + 1))
  printf 'count\n' >> "$EVENTS"
  if [ "${seq[$idx]}" = fail ]; then
    PD_HELD="?"
    PD_COUNT_DETAIL="ioclasscount rc=1 raw=fake"
    return 1
  fi
  PD_HELD="${seq[$idx]}"
}
settle_run() {
  FAKE_PD_SEQUENCE="$1"
  pd_reads=0
  : > "$EVENTS"
  TEARDOWN_REBOOT=0
  if cluster_teardown > "$tmp/pd-settle.log" 2>&1; then
    settle_rc=0
  else
    settle_rc=$?
  fi
  settle_sleeps="$(grep -c '^sleep$' "$EVENTS" || true)"
  settle_reads="$(grep -c '^count$' "$EVENTS" || true)"
}

settle_run '1 0'
check 'PD released inside the window returns success' 0 "$settle_rc"
check 'PD released inside the window stops re-reading after one sleep' 1 "$settle_sleeps"
check 'PD released inside the window reads twice' 2 "$settle_reads"
check 'PD released inside the window sets no reboot' 0 "$TEARDOWN_REBOOT"
contains 'PD release logs the final count' 'cluster-teardown: PD held=0 after 1s' "$(cat "$tmp/pd-settle.log")"
check 'PD released inside the window logs no reboot request' 0 "$(grep -c 'reboot before the next join' "$tmp/pd-settle.log" || true)"
set +e
(cluster_detach_finish 0 0 "$TEARDOWN_REBOOT" false)
detach_rc=$?
set -e
check 'PD released inside the window does not exit 3' 0 "$detach_rc"

settle_run '1'
check 'stranded PD waits the full 30 s window' 30 "$settle_sleeps"
check 'stranded PD reads once plus once per second' 31 "$settle_reads"
check 'stranded PD sets the reboot flag' 1 "$TEARDOWN_REBOOT"
check 'stranded PD teardown is not a failure' 0 "$settle_rc"
contains 'stranded PD logs the final count' 'cluster-teardown: PD held=1 after 30s' "$(cat "$tmp/pd-settle.log")"
contains 'stranded PD requests a reboot before the next join' 'reboot before the next join' "$(cat "$tmp/pd-settle.log")"
set +e
(cluster_detach_finish 0 0 "$TEARDOWN_REBOOT" false)
detach_rc=$?
set -e
check 'stranded PD exits 3' 3 "$detach_rc"

settle_run '1 fail'
check 'unreadable re-read fails teardown' 1 "$settle_rc"
check 'unreadable re-read stops the wait at the failed read' 1 "$settle_sleeps"
contains 'unreadable re-read refuses with pd-count-unreadable' 'REFUSE reason=pd-count-unreadable' "$(cat "$tmp/pd-settle.log")"

if [ "$fail" -ne 0 ]; then
  echo 'teardown recovery checks FAILED' >&2
  exit 1
fi
echo 'teardown recovery checks passed'
