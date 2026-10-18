#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"

cat > "$tmp/bin/launchctl" <<'LAUNCHCTL'
#!/usr/bin/env bash
case "$1" in
  list)
    printf 'PID Status Label\n'
    printf '11 0 application.com.example.one.1.2\n'
    printf '12 0 application.com.example.two.3.4\n'
    ;;
  bootout)
    printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_LOG"
    case "$*" in *application.com.example.two.3.4*) exit 17 ;; esac
    ;;
  print) exit 1 ;;
esac
LAUNCHCTL
cat > "$tmp/bin/sysctl" <<'SYSCTL'
#!/usr/bin/env bash
printf 'vm.swapusage: total = 0M used = 0M free = 1M\n'
SYSCTL
cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
exit 0
CURL
cat > "$tmp/bin/pgrep" <<'PGREP'
#!/usr/bin/env bash
exit 0
PGREP
cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
exit 0
CURL
chmod +x "$tmp/bin/launchctl" "$tmp/bin/sysctl" "$tmp/bin/curl" "$tmp/bin/pgrep"

source modules/mlx/scripts/cluster-join.sh
source modules/mlx/scripts/cluster-room.sh

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
export CLUSTER_LAUNCHCTL_BIN="$tmp/bin/launchctl"
export CLUSTER_SYSCTL_BIN="$tmp/bin/sysctl"
export CLUSTER_PGREP_BIN="$tmp/bin/pgrep"
export CLUSTER_AWK_BIN=awk
export CLUSTER_SED_BIN=sed
export CLUSTER_GREP_BIN=grep
export CLUSTER_QUIESCE_APPS='com.example.one com.example.two'
export CLUSTER_QUIESCE_LAUNCHD='org.example.agent'
export CLUSTER_QUIESCE_GRACE_SECS=0
export CLUSTER_JOIN_SWAP_THRESHOLD_MB=8000
export CLUSTER_SHARD_MEMORY_MB=0
export CLUSTER_SERVER_LABELS=''
export CLUSTER_WATCHDOG_LABEL=''
export CLUSTER_RANK_PROCESS_PATTERN=/fake-rank
export FAKE_LAUNCHCTL_LOG="$tmp/launchctl.log"
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
contains 'room check continued after bootout failure' 'cluster-join: room PASS' "$output"
failure_line="$(grep -n 'quiesce app application.com.example.two.3.4 rc=17' "$tmp/output.log" | cut -d: -f1)"
room_line="$(grep -n 'cluster-join: room PASS' "$tmp/output.log" | cut -d: -f1)"
check 'room check follows the logged bootout failure' yes "$([ "$failure_line" -lt "$room_line" ] && echo yes || echo no)"
check 'only configured agent recorded for restore' org.example.agent "$(cat "$tmp/state/quiesced-agents")"

if [ "$fail" -ne 0 ]; then
  echo 'quiesce checks FAILED' >&2
  exit 1
fi
echo 'quiesce checks passed'
