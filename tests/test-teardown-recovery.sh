#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state" "$tmp/home/Library/LaunchAgents"

cat > "$tmp/bin/launchctl" <<'LAUNCHCTL'
#!/usr/bin/env bash
printf 'launchctl %s\n' "$*" >> "$EVENTS"
if [ "${1:-}" = kill ] && [ "${2:-}" = SIGKILL ]; then touch "$SIGKILL_MARKER"; fi
LAUNCHCTL
cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
case " $* " in
  *' -X POST '*) printf '{"usage":{"completion_tokens":1}}' ;;
esac
CURL
cat > "$tmp/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf 'ssh %s\n' "$*" >> "$EVENTS"
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
exit "${FAKE_SSH_RC:-0}"
SSH
cat > "$tmp/bin/sysctl" <<'SYSCTL'
#!/usr/bin/env bash
case "${1:-}" in
  *swapusage*) printf 'vm.swapusage: total = 0M used = 0M free = 1M\n' ;;
  *) printf '0\n' ;;
esac
SYSCTL
chmod +x "$tmp/bin/launchctl" "$tmp/bin/curl" "$tmp/bin/ssh" "$tmp/bin/sysctl"

source modules/mlx/scripts/cluster-teardown.sh
source modules/mlx/scripts/cluster-detach.sh
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
export CLUSTER_LIFECYCLE_LOG="$tmp/lifecycle.log"
export FAKE_SSH_LOG="$tmp/ssh.log"
export CLUSTER_SSH_BIN="$tmp/bin/ssh"
export CLUSTER_ROLE=worker
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_STANDALONE_WIRED_LIMIT_MB=0
export CLUSTER_RANK_LABEL=dev.test.rank
export CLUSTER_RANK_PROCESS_PATTERN=/fake-rank
export CLUSTER_DETACH_TIMEOUT_SECS=0
export CLUSTER_STANDALONE_PROBE_URL=http://127.0.0.1:1
export CLUSTER_STANDALONE_PROBE_MODEL=test
export CLUSTER_DETACH_SWAP_THRESHOLD_MB=20000
export CLUSTER_PEER_STATE_FILE="$tmp/state/peer-state.json"
export CLUSTER_SOFTWARE_JSON='{"nix_ai":"a","nix_darwin":"b","mlx":"c","mlx_lm":"d","macos":"e"}'
export CLUSTER_SW_VERS_BIN=/usr/bin/true
export CLUSTER_DARWIN_VERSION_BIN=/usr/bin/false
export CLUSTER_IOCLASSCOUNT_BIN="$tmp/bin/ioclasscount"
cat > "$CLUSTER_IOCLASSCOUNT_BIN" <<'IOCLASS'
#!/usr/bin/env bash
printf '%s = 0\n' "$1"
IOCLASS
chmod +x "$CLUSTER_IOCLASSCOUNT_BIN"
export CLUSTER_PGREP_BIN="$tmp/bin/pgrep"
cat > "$CLUSTER_PGREP_BIN" <<'PGREP'
#!/usr/bin/env bash
[ -f "$SIGKILL_MARKER" ] && exit 1
printf '123\n'
PGREP
export CLUSTER_KILL_BIN="$tmp/bin/kill"
cat > "$CLUSTER_KILL_BIN" <<'KILL'
#!/usr/bin/env bash
exit 0
KILL
export CLUSTER_PKILL_BIN="$tmp/bin/pkill"
cat > "$CLUSTER_PKILL_BIN" <<'PKILL'
#!/usr/bin/env bash
exit 0
PKILL
chmod +x "$CLUSTER_PGREP_BIN" "$CLUSTER_KILL_BIN" "$CLUSTER_PKILL_BIN"

: > "$EVENTS"
printf 'label-a\nlabel-b\n' > "$tmp/state/quiesced-agents"
touch "$tmp/home/Library/LaunchAgents/label-a.plist"
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
contains 'teardown order' 'disarm stop count ceiling restore-serving launchctl bootstrap gui/'"$(id -u)"' '"$tmp/home/Library/LaunchAgents/label-a.plist"' launchctl kickstart gui/'"$(id -u)"'/label-b link-down' "$ordered"
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
sleep() { :; }
if rank_stop_verified; then
  check 'rank_stop_verified completes after fake SIGKILL' 0 "$?"
else
  echo '  FAIL fake SIGKILL did not prove rank absence'; fail=1
fi
check 'SIGKILL sets the reboot-required flag' 1 "$TEARDOWN_REBOOT"
set +e
(cluster_detach_finish 0 false "$TEARDOWN_REBOOT" false)
detach_rc=$?
set -e
check 'SIGKILL teardown exits with reboot code' 3 "$detach_rc"

echo 'coordinator detaches the worker only after local teardown and returns 3 on remote failure:'
: > "$EVENTS"
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
export CLUSTER_ROLE=coordinator
export CLUSTER_PEER_SSH=user@worker
export CLUSTER_STANDALONE_PROBE_URL=http://127.0.0.1:1
export CLUSTER_STANDALONE_PROBE_MODEL=test
export CLUSTER_DETACH_SWAP_THRESHOLD_MB=20000
export CLUSTER_DETACH_TIMEOUT_SECS=10
export FAKE_SSH_RC=42
cluster_teardown() { printf 'local-teardown\n' >> "$EVENTS"; TEARDOWN_REBOOT=0; return 0; }
cluster_lifecycle_log_start() { exec > "$CLUSTER_LIFECYCLE_LOG" 2>&1; }
set +e
(cluster_detach_main)
detach_rc=$?
set -e
check 'remote detach failure exits with code 3' 3 "$detach_rc"
check 'coordinator issued one worker detach' 1 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"
check 'worker detach arguments' '-o BatchMode=yes -o ConnectTimeout=10 user@worker cluster-detach --worker' "$(cat "$FAKE_SSH_LOG")"
contains 'remote failure is logged' 'peer-detach-failed rc=42' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
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

if [ "$fail" -ne 0 ]; then
  echo 'teardown recovery checks FAILED' >&2
  exit 1
fi
echo 'teardown recovery checks passed'
