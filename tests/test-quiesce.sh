#!/usr/bin/env bash
set -euo pipefail

# The sourced cluster-join functions read these; shellcheck cannot see that from this file.
export PD_GATE_REASON PD_COUNT_DETAIL JOIN_SESSION_ID

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"

write_stub() {
  printf '#!%s\n' "$BASH" > "$1"
  cat >> "$1"
}

write_stub "$tmp/bin/launchctl" <<'LAUNCHCTL'
printf '%s\n' "$*" >> "${FAKE_LAUNCHCTL_ALL:-/dev/null}"
case "$1" in
  list)
    printf 'PID Status Label\n'
    printf '11 0 application.com.example.one.1.2\n'
    printf '12 0 application.com.example.two.3.4\n'
    ;;
  kickstart)
    printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_LOG"
    ;;
  bootout)
    printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_LOG"
    case "$*" in *application.com.example.two.3.4*) exit 17 ;; esac
    ;;
  print)
    label="${2##*/}"
    [ "$label" = org.example.agent ] || exit 1
    grep -q "/$label\$" "$FAKE_LAUNCHCTL_LOG" && exit 1
    printf '%s = {\n\tpath = %s\n}\n' "$2" "$FAKE_AGENT_PLIST"
    ;;
  print-disabled)
    if [ -n "${FAKE_DISABLED_LABELS:-}" ]; then
      printf '%s\n' "$FAKE_DISABLED_LABELS"
    fi
    ;;
esac
LAUNCHCTL
write_stub "$tmp/bin/sysctl" <<'SYSCTL'
if [ "${1:-}" = -w ]; then
  printf '%s\n' "$*" >> "${FAKE_SYSCTL_WRITES:-/dev/null}"
  [ -z "${FAKE_WIRED_FILE:-}" ] || printf '%s\n' "${2#*=}" > "$FAKE_WIRED_FILE"
  exit 0
fi
case "${2:-}" in
  kern.boottime) printf '{ sec = 100, usec = 0 }\n' ;;
  hw.memsize) printf '%s\n' "${FAKE_MEMSIZE:-0}" ;;
  iogpu.wired_limit_mb)
    if [ -n "${FAKE_WIRED_FILE:-}" ] && [ -f "$FAKE_WIRED_FILE" ]; then cat "$FAKE_WIRED_FILE"; else printf '0\n'; fi
    ;;
  *) printf 'vm.swapusage: total = 0M used = 0M free = 1M\n' ;;
esac
SYSCTL
write_stub "$tmp/bin/curl" <<'CURL'
exit 0
CURL
write_stub "$tmp/bin/pgrep" <<'PGREP'
exit 0
PGREP
write_stub "$tmp/bin/vm_stat" <<'VMSTAT'
printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\n'
printf 'Pages free:                              %s.\n' "${FAKE_FREE_PAGES:-0}"
printf 'Pages inactive:                          0.\n'
printf 'Pages speculative:                       0.\n'
printf 'Pages wired down:                        0.\n'
VMSTAT
write_stub "$tmp/bin/sudo" <<'SUDO'
[ "${1:-}" = -n ] && shift
"$@"
SUDO
write_stub "$tmp/bin/curl" <<'CURL'
case "$*" in
  *chat/completions*) printf '{"usage":{"completion_tokens":1}}\n' ;;
esac
exit 0
CURL
chmod +x "$tmp/bin/launchctl" "$tmp/bin/sysctl" "$tmp/bin/curl" "$tmp/bin/pgrep" "$tmp/bin/vm_stat" "$tmp/bin/sudo"

# shellcheck source=modules/mlx/scripts/cluster-join.sh
source modules/mlx/scripts/cluster-join.sh
# shellcheck source=modules/mlx/scripts/cluster-boot-scope.sh
source modules/mlx/scripts/cluster-boot-scope.sh
# shellcheck source=modules/mlx/scripts/cluster-teardown.sh
source modules/mlx/scripts/cluster-teardown.sh
# shellcheck source=modules/mlx/scripts/cluster-room.sh
source modules/mlx/scripts/cluster-room.sh
# shellcheck source=modules/mlx/scripts/cluster-serving-restore.sh
source modules/mlx/scripts/cluster-serving-restore.sh
# shellcheck source=modules/mlx/scripts/cluster-detach.sh
source modules/mlx/scripts/cluster-detach.sh

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

export CLUSTER_ROLE=coordinator
export PATH="$tmp/bin:$PATH"
export CLUSTER_PEER_SSH=''
export CLUSTER_STATE_DIR="$tmp/state"
export CLUSTER_STATE_FILE="$tmp/state/link-state"
export CLUSTER_PEER_STATE_FILE="$tmp/state/peer-state.json"
export HF_HOME="$tmp/hf"
export CLUSTER_MODEL=org/default
export CLUSTER_SHARDING_MODE=tensor
export CLUSTER_SHARD_MEMORY_MB=0
export CLUSTER_WIRED_LIMIT_MB=2000
export CLUSTER_COMPOSITOR_RESERVE_MB=100
# The module always declares the floor; 0 is its default and turns it off.
export CLUSTER_MEMORY_FLOOR_PCT=0
export CLUSTER_LAUNCHCTL_BIN="$tmp/bin/launchctl"
export CLUSTER_SYSCTL_BIN="$tmp/bin/sysctl"
export CLUSTER_PGREP_BIN="$tmp/bin/pgrep"
export CLUSTER_CURL_BIN="$tmp/bin/curl"
export CLUSTER_AWK_BIN=awk
export CLUSTER_SED_BIN=sed
export CLUSTER_GREP_BIN=grep
export CLUSTER_QUIESCE_APPS='com.example.one com.example.two'
export CLUSTER_QUIESCE_LAUNCHD='org.example.absent org.example.agent'
export CLUSTER_DECLARED_AGENT_LABELS='org.example.agent'
export FAKE_AGENT_PLIST="$tmp/Some App.app/Contents/Library/LaunchAgents/org.example.agent.plist"
export CLUSTER_QUIESCE_GRACE_SECS=0
export CLUSTER_JOIN_SWAP_THRESHOLD_MB=8000
export CLUSTER_SHARD_MEMORY_MB=0
export CLUSTER_SERVER_LABELS=''
export CLUSTER_WATCHDOG_LABEL=''
export CLUSTER_RANK_PROCESS_PATTERN=/fake-rank
export FAKE_LAUNCHCTL_LOG="$tmp/launchctl.log"
model_cache="$HF_HOME/hub/models--org--default"
model_revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$model_cache/refs" "$model_cache/snapshots/$model_revision"
printf '%s\n' "$model_revision" > "$model_cache/refs/main"
printf '{}\n' > "$model_cache/snapshots/$model_revision/config.json"
: > "$model_cache/snapshots/$model_revision/weights.safetensors"
uid="$(id -u)"
mkdir -p "$tmp/home/Library/LaunchAgents"
touch "$tmp/home/Library/LaunchAgents/org.example.agent.plist"
export HOME="$tmp/home"
: > "$FAKE_LAUNCHCTL_LOG"
printf 'up\n' > "$CLUSTER_STATE_FILE"
pd_start_gate() { :; }
link_prep_ok() { :; }
set_wired_limit() { :; }
peer_state_write() { return 1; }
link_state_write() { :; }
cluster_teardown() { :; }
cluster_lifecycle_log_start() { :; }
pd_start_gate
link_prep_ok
set_wired_limit
peer_state_write true 1000 || true
link_state_write up
cluster_teardown
cluster_lifecycle_log_start

if (cluster_join_main) > "$tmp/output.log" 2>&1; then
  echo '  FAIL test join proceeded after its J6 publication was refused'
  fail=1
fi

launched="$(cat "$FAKE_LAUNCHCTL_LOG")"
contains 'first fake app booted out' 'gui/'"$uid"'/application.com.example.one.1.2' "$launched"
contains 'second fake app booted out' 'gui/'"$uid"'/application.com.example.two.3.4' "$launched"
contains 'configured launchd agent booted out' 'gui/'"$uid"'/org.example.agent' "$launched"
output="$(cat "$tmp/output.log")"
contains 'app action logged' 'cluster-join: quiesce app application.com.example.one.1.2 rc=0' "$output"
contains 'agent action logged' 'cluster-join: quiesce launchd org.example.agent rc=0' "$output"
contains 'bootout failure logged' 'cluster-join: quiesce app application.com.example.two.3.4 rc=17' "$output"
contains 'room gate refused its unconfigured shard after bootout failure' \
  'cluster-join: REFUSE reason=room-unconfigured' "$output"
failure_line="$(grep -n 'quiesce app application.com.example.two.3.4 rc=17' "$tmp/output.log" | cut -d: -f1)"
room_line="$(grep -n 'REFUSE reason=room-unconfigured' "$tmp/output.log" | cut -d: -f1)"
check 'room check follows the logged bootout failure' yes "$([ "$failure_line" -lt "$room_line" ] && echo yes || echo no)"
contains 'undeclared agent skipped' 'cluster-join: quiesce launchd org.example.absent not declared on this host; skipped' "$output"
check 'only declared configured agent recorded with its plist' "org.example.agent $FAKE_AGENT_PLIST" "$(cat "$tmp/state/quiesced-agents")"

# A declared serving label that is disabled must refuse the join before anything is booted out.
: > "$FAKE_LAUNCHCTL_LOG"
export CLUSTER_SERVER_LABELS='org.example.agent'
export FAKE_DISABLED_LABELS='"org.example.agent" => disabled'
join_disabled_rc=0
(cluster_join_main) > "$tmp/join-disabled.log" 2>&1 || join_disabled_rc=$?
export CLUSTER_SERVER_LABELS=''
unset FAKE_DISABLED_LABELS
join_disabled_out="$(cat "$tmp/join-disabled.log")"
check 'join exits non-zero on a disabled serving label' 1 "$join_disabled_rc"
contains 'disabled serving label named in refusal' \
  'REFUSE reason=serving-label-disabled detail=declared label org.example.agent is disabled' "$join_disabled_out"
check 'join boots out nothing when a serving label is disabled' "" "$(cat "$FAKE_LAUNCHCTL_LOG")"

echo 'a host under its memory floor refuses before the wired ceiling, quiesce or any rank start:'
export CLUSTER_VMSTAT_BIN="$tmp/bin/vm_stat"
export CLUSTER_SUDO_BIN="$tmp/bin/sudo"
export FAKE_SYSCTL_WRITES="$tmp/sysctl-writes"
export FAKE_MEMSIZE=137438953472
export CLUSTER_MEMORY_FLOOR_PCT=25
export FAKE_LAUNCHCTL_ALL="$tmp/launchctl-all"
export FAKE_WIRED_FILE="$tmp/wired-limit"
export FAKE_STATE_LOG="$tmp/state-writes"
# Runs one join with every host change recorded: each launchctl subcommand, each sysctl write, and each teardown,
# peer-state or link-state call. Arguments go to cluster_join_main.
floor_join() {
  : > "$FAKE_LAUNCHCTL_LOG"
  : > "$FAKE_LAUNCHCTL_ALL"
  : > "$FAKE_SYSCTL_WRITES"
  : > "$FAKE_STATE_LOG"
  rm -f "$tmp/state/quiesced-agents" "$FAKE_WIRED_FILE"
  floor_rc=0
  (
    unset -f set_wired_limit
    # shellcheck source=modules/mlx/scripts/cluster-wired-limit.sh
    source modules/mlx/scripts/cluster-wired-limit.sh
    pd_start_gate() {
      case "${FAKE_J1_REFUSE:-}" in
        rank-alive)
          PD_GATE_REASON=rank-alive
          PD_COUNT_DETAIL='pids=4242'
          ;;
        pd-reserve)
          PD_GATE_REASON=pd-reserve
          PD_COUNT_DETAIL='the next rank PD would reach the configured reserve'
          PD_REBOOT=1
          ;;
        *) return 0 ;;
      esac
      return 1
    }
    # The coordinator's published session state as the worker reads it: FAKE_COORD_PHASE set means it exists and
    # matches this session; unset means the worker cannot read it.
    peer_state_session_read() {
      PEER_PHASE="${FAKE_COORD_PHASE:-}"
      PEER_GATE_REASON=""
      [ -n "$PEER_PHASE" ] || {
        PEER_GATE_REASON=peer-state-unreachable
        return 1
      }
    }
    link_prep_ok() { [ -z "${FAKE_J2_REFUSE:-}" ]; }
    cluster_teardown() { printf 'teardown\n' >> "$FAKE_STATE_LOG"; }
    peer_state_write() { printf 'peer-state %s\n' "$*" >> "$FAKE_STATE_LOG"; return 1; }
    link_state_write() { printf 'link-state %s\n' "$1" >> "$FAKE_STATE_LOG"; }
    # The join reaches the recorders through its exit trap; one direct call each keeps them visible to shellcheck.
    cluster_teardown
    : > "$FAKE_STATE_LOG"
    cluster_join_main "$@"
  ) > "$tmp/join-floor.log" 2>&1 || floor_rc=$?
  floor_out="$(cat "$tmp/join-floor.log")"
}
no_host_change() {
  check "$1: no sysctl write" 0 "$(wc -l < "$FAKE_SYSCTL_WRITES" | tr -d ' ')"
  check "$1: no launchctl call of any kind" "" "$(cat "$FAKE_LAUNCHCTL_ALL")"
  check "$1: no teardown, peer-state or link-state write" "" "$(cat "$FAKE_STATE_LOG")"
  check "$1: never reaches the wired ceiling" 0 "$(grep -c 'J3 wired-ceiling' "$tmp/join-floor.log" || true)"
  check "$1: records no quiesced agent" no "$([ -e "$tmp/state/quiesced-agents" ] && echo yes || echo no)"
}
# 25% of 131072MB is 32768MB; 1000 pages of 16384 bytes is 15MB.
FAKE_FREE_PAGES=1000 floor_join
check 'join under the floor exits 1' 1 "$floor_rc"
contains 'floor refusal is a guard line' 'cluster-join: guard=J2a decision=refuse reason=memory-floor' "$floor_out"
contains 'floor refusal names the shortfall' 'REFUSE reason=memory-floor detail=15MB free' "$floor_out"
no_host_change 'coordinator floor refusal'

echo 'a worker under its memory floor refuses with no teardown, even with its session already set:'
FAKE_FREE_PAGES=1000 CLUSTER_ROLE=worker floor_join --worker --session 20261111T020000Z-0123abcd
check 'worker join under the floor exits 4 (refused, untouched)' 4 "$floor_rc"
contains 'worker floor refusal is a guard line' 'cluster-join: guard=J2a decision=refuse reason=memory-floor' "$floor_out"
no_host_change 'worker floor refusal'

echo 'a stale worker rank at J1 goes to the exit teardown; a coordinator rank at J1 changes nothing:'
worker_session=(--worker --session 20261111T020000Z-0123abcd)
FAKE_COORD_PHASE=preparing FAKE_J1_REFUSE=rank-alive CLUSTER_ROLE=worker floor_join "${worker_session[@]}"
check 'worker J1 rank-alive refusal exits 1' 1 "$floor_rc"
contains 'worker J1 refusal names the live rank' 'REFUSE reason=rank-alive detail=pids=4242' "$floor_out"
contains 'worker J1 logs the stale-rank decision' 'cluster-join: guard=J1 decision=teardown reason=stale-worker-rank coordinator-phase=preparing' "$floor_out"
check 'worker J1 stale rank runs the exit teardown once' teardown "$(cat "$FAKE_STATE_LOG")"
check 'worker J1 stale rank: no sysctl write from the join' 0 "$(wc -l < "$FAKE_SYSCTL_WRITES" | tr -d ' ')"
check 'worker J1 stale rank: never reaches the wired ceiling' 0 "$(grep -c 'J3 wired-ceiling' "$tmp/join-floor.log" || true)"
FAKE_J1_REFUSE=rank-alive floor_join
check 'coordinator J1 rank-alive refusal exits 1' 1 "$floor_rc"
check 'coordinator J1 logs no stale-rank decision' 0 "$(grep -c 'decision=teardown reason=stale-worker-rank' "$tmp/join-floor.log" || true)"
no_host_change 'coordinator J1 rank-alive refusal'
echo 'a worker rank at J1 without the coordinator session published is not proven stale and is left alone:'
FAKE_J1_REFUSE=rank-alive CLUSTER_ROLE=worker floor_join "${worker_session[@]}"
check 'worker J1 rank-alive without coordinator state exits 4 (refused, untouched)' 4 "$floor_rc"
contains 'worker J1 logs the unconfirmed stale rank' \
  'cluster-join: guard=J1 decision=refuse reason=stale-worker-rank-unconfirmed coordinator=peer-state-unreachable' "$floor_out"
check 'worker J1 rank-alive without coordinator state logs no teardown decision' 0 \
  "$(grep -c 'decision=teardown reason=stale-worker-rank' "$tmp/join-floor.log" || true)"
no_host_change 'worker J1 rank-alive without coordinator state'
FAKE_COORD_PHASE=abort FAKE_J1_REFUSE=rank-alive CLUSTER_ROLE=worker floor_join "${worker_session[@]}"
check 'worker J1 rank-alive with an aborted coordinator session exits 4' 4 "$floor_rc"
no_host_change 'worker J1 rank-alive with an aborted coordinator session'
echo 'a worker pd-reserve refusal at J1 changed nothing and exits untouched; the coordinator still exits 3:'
FAKE_J1_REFUSE=pd-reserve CLUSTER_ROLE=worker floor_join "${worker_session[@]}"
check 'worker J1 pd-reserve refusal exits 4 (refused, untouched)' 4 "$floor_rc"
contains 'worker J1 pd-reserve refusal is logged' 'REFUSE reason=pd-reserve' "$floor_out"
no_host_change 'worker J1 pd-reserve refusal'
FAKE_J1_REFUSE=pd-reserve floor_join
check 'coordinator J1 pd-reserve refusal exits 3' 3 "$floor_rc"
no_host_change 'coordinator J1 pd-reserve refusal'
echo 'every other worker refusal before J3 changes nothing on this host and runs no teardown:'
FAKE_J2_REFUSE=1 CLUSTER_ROLE=worker floor_join "${worker_session[@]}"
check 'worker J2 link-prep refusal exits 4 (refused, untouched)' 4 "$floor_rc"
contains 'worker J2 refusal is logged' 'REFUSE reason=link-prep-not-ready' "$floor_out"
no_host_change 'worker J2 link-prep refusal'
CLUSTER_MODEL=org/missing CLUSTER_ROLE=worker floor_join "${worker_session[@]}"
check 'worker model-select refusal exits 4 (refused, untouched)' 4 "$floor_rc"
check 'worker model-select refusal stops before J1' 0 "$(grep -c 'J1 pd-start-gate' "$tmp/join-floor.log" || true)"
no_host_change 'worker model-select refusal'

echo 'the J6 publish marks published state before its first write, so a later refusal runs teardown:'
state_written=false
JOIN_SESSION_ID=20261111T020000Z-0123abcd
cluster_join_publish_preparing > /dev/null 2>&1 || true
check 'J6 publish sets the published-state flag' true "$state_written"
quiesced=false
(cluster_join_quiesce > /dev/null 2>&1; printf '%s\n' "$quiesced" > "$tmp/quiesced-flag") || true
check 'J4 quiesce sets the quiesced flag before it changes anything' true "$(cat "$tmp/quiesced-flag")"

# Positive control. 2097152 pages is exactly the 32768MB floor, so J2a passes. The sysctl stub reads back the value
# J3 wrote, so J3 passes and the recorders see its write and the J4 quiesce; the join then refuses at J5 on its
# unconfigured shard. This proves the recorders above would have caught a change.
FAKE_FREE_PAGES=2097152 floor_join
contains 'a host at its floor passes J2a' 'cluster-join: guard=J2a decision=pass reason=memory-floor-met' "$floor_out"
contains 'a host at its floor passes the wired ceiling' 'cluster-join: guard=J3 decision=pass reason=wired-ceiling-set' "$floor_out"
check 'the sysctl write recorder sees the J3 write' yes "$([ -s "$FAKE_SYSCTL_WRITES" ] && echo yes || echo no)"
check 'the launchctl recorder sees the J4 quiesce' yes "$([ -s "$FAKE_LAUNCHCTL_ALL" ] && echo yes || echo no)"
check 'the state recorder sees the teardown after a later refusal' yes "$(grep -q '^teardown$' "$FAKE_STATE_LOG" && echo yes || echo no)"
export CLUSTER_MEMORY_FLOOR_PCT=0
FAKE_FREE_PAGES=0 floor_join
contains 'a declared 0 floor logs its pass' 'cluster-join: guard=J2a decision=pass reason=memory-floor-off' "$floor_out"
for declared in empty unset; do
  if [ "$declared" = empty ]; then export CLUSTER_MEMORY_FLOOR_PCT=''; else unset CLUSTER_MEMORY_FLOOR_PCT; fi
  FAKE_FREE_PAGES=2097152 floor_join
  contains "an $declared floor refuses at J2a" 'cluster-join: guard=J2a decision=refuse reason=memory-floor' "$floor_out"
  contains "an $declared floor names the missing declaration" 'unset or empty' "$floor_out"
  check "an $declared floor exits 1" 1 "$floor_rc"
  check "an $declared floor writes no sysctl value" no "$([ -s "$FAKE_SYSCTL_WRITES" ] && echo yes || echo no)"
  check "an $declared floor quiesces nothing" no "$([ -s "$FAKE_LAUNCHCTL_ALL" ] && echo yes || echo no)"
done
export CLUSTER_MEMORY_FLOOR_PCT=0
unset FAKE_LAUNCHCTL_ALL FAKE_WIRED_FILE

# Detach verifies each declared serving label; the stubs below stand in for the D3/D4 readings.
pd_held_count() { PD_HELD=0; }
pd_held_count
check 'PD count fixture reports zero' 0 "$PD_HELD"
rank_process_absent() { return 0; }
export CLUSTER_DETACH_TIMEOUT_SECS=30

# A declared serving label that is not loaded must fail detach and be named in the refusal.
: > "$FAKE_LAUNCHCTL_LOG"
export CLUSTER_STANDALONE_PROBES='org.example.absent http://127.0.0.1:9/v1 org/default'
detach_rc=0
(cluster_detach_main) > "$tmp/detach-missing.log" 2>&1 || detach_rc=$?
detach_missing_out="$(cat "$tmp/detach-missing.log")"
check 'detach exits non-zero on a missing declared serving label' 1 "$detach_rc"
contains 'missing serving label named in refusal' \
  'REFUSE reason=serving-label-not-loaded detail=declared label org.example.absent is not loaded' "$detach_missing_out"
check 'detach does not claim restored serving when a label is missing' 0 \
  "$(grep -c 'standalone serving restored' "$tmp/detach-missing.log" || true)"

# With every declared serving label loaded, enabled and completing, detach prints the restored line exactly once.
: > "$FAKE_LAUNCHCTL_LOG"
export CLUSTER_STANDALONE_PROBES='org.example.agent http://127.0.0.1:9/v1 org/default'
detach_rc=0
(cluster_detach_main) > "$tmp/detach-healthy.log" 2>&1 || detach_rc=$?
check 'detach exits zero when every declared serving label is healthy' 0 "$detach_rc"
check 'detach prints the restored line once when healthy' 1 \
  "$(grep -c 'standalone serving restored (real completion verified)' "$tmp/detach-healthy.log" || true)"

if [ "$fail" -ne 0 ]; then
  echo 'quiesce checks FAILED' >&2
  exit 1
fi
echo 'quiesce checks passed'
