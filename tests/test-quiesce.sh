#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"

write_stub() {
  printf '#!%s\n' "$BASH" > "$1"
  cat >> "$1"
}

write_stub "$tmp/bin/launchctl" <<'LAUNCHCTL'
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
case "${2:-}" in
  kern.boottime) printf '{ sec = 100, usec = 0 }\n' ;;
  *) printf 'vm.swapusage: total = 0M used = 0M free = 1M\n' ;;
esac
SYSCTL
write_stub "$tmp/bin/curl" <<'CURL'
exit 0
CURL
write_stub "$tmp/bin/pgrep" <<'PGREP'
exit 0
PGREP
write_stub "$tmp/bin/curl" <<'CURL'
case "$*" in
  *chat/completions*) printf '{"usage":{"completion_tokens":1}}\n' ;;
esac
exit 0
CURL
chmod +x "$tmp/bin/launchctl" "$tmp/bin/sysctl" "$tmp/bin/curl" "$tmp/bin/pgrep"

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

# Detach verifies each declared serving label; the stubs below stand in for the D3/D4 readings.
pd_held_count() { PD_HELD=0; }
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
  'REFUSE reason=serving-label-not-loaded detail=declared serving label org.example.absent is not loaded' "$detach_missing_out"
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
