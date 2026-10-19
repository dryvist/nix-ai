#!/usr/bin/env bash
set -euo pipefail

# The sourced cluster-join and cluster-teardown functions read these; shellcheck cannot see that from this file.
export JOIN_REBOOT JOIN_MODEL_EXPLICIT JOIN_EXIT_ACTIVE JOIN_SIGNAL_RC CLUSTER_PEER_SSH_RC \
  CLUSTER_COORDINATOR_LEASE_SECS COORDINATOR_LEASE_TS formed ceiling_attempted quiesced

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state" "$tmp/hf/hub/models--org--default/refs" \
  "$tmp/hf/hub/models--org--default/snapshots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
  "$tmp/hf/hub/models--user--override/refs" \
  "$tmp/hf/hub/models--user--override/snapshots/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

write_stub() {
  printf '#!%s\n' "$BASH" > "$1"
  cat >> "$1"
}

write_stub "$tmp/bin/curl" <<'CURL'
case "$*" in
  *"http://$CLUSTER_STATIC_PEER_IP:"*)
    [ -f "$FAKE_PEER_STATE_FILE" ] || exit 7
    cat "$FAKE_PEER_STATE_FILE"
    ;;
  *http://127.0.0.1:*) exit "${FAKE_HTTP_RC:-7}" ;;
  *) exit 1 ;;
esac
CURL
write_stub "$tmp/bin/launchctl" <<'LAUNCHCTL'
printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_LOG"
if [ "${1:-}" = print ]; then printf 'state = running\n'; fi
if [ "${1:-}" = kickstart ]; then exit "${FAKE_KICKSTART_RC:-${FAKE_LAUNCHCTL_RC:-0}}"; fi
exit "${FAKE_LAUNCHCTL_RC:-0}"
LAUNCHCTL
write_stub "$tmp/bin/stat" <<'STAT'
printf '%s\n' "$FAKE_MTIME"
STAT
write_stub "$tmp/bin/sw-vers" <<'SWVERS'
printf 'build-a\n'
SWVERS
write_stub "$tmp/bin/darwin-version" <<'DARWINVERSION'
printf '{"configurationRevision":"%s"}\n' "${FAKE_CONFIG_REV:-config-a}"
DARWINVERSION
write_stub "$tmp/bin/model-stat" <<'MODELSTAT'
printf '%s\n' "${FAKE_MODEL_SIZE:-1}"
MODELSTAT
write_stub "$tmp/bin/pgrep" <<'PGREP'
if [ -n "${FAKE_PGREP_SEQUENCE:-}" ]; then
  n="$(cat "$FAKE_PGREP_COUNT_FILE" 2>/dev/null || printf '0')"
  n=$((n + 1))
  printf '%s\n' "$n" > "$FAKE_PGREP_COUNT_FILE"
  state="$(sed -n "${n}p" "$FAKE_PGREP_SEQUENCE")"
else
  state="${FAKE_PGREP_STATE:-absent}"
fi
case "$state" in
  running) printf '123\n'; exit 0 ;;
  absent) exit 1 ;;
  *) exit 2 ;;
esac
PGREP
write_stub "$tmp/bin/ibv-devinfo" <<'IBV'
printf 'hca_id: rdma_test\nmax_pd: 11\n'
IBV
write_stub "$tmp/bin/ioclasscount" <<'IOCLASS'
printf '%s = %s\n' "$1" "${FAKE_PD_HELD:-0}"
IOCLASS
write_stub "$tmp/bin/sysctl" <<'SYSCTL'
case "${1:-}" in
  -n)
    case "${2:-}" in
      vm.swapusage) printf 'vm.swapusage: total = 0M used = 0M free = 1M\n' ;;
      iogpu.wired_limit_mb) cat "$FAKE_WIRED_FILE" ;;
      kern.boottime) printf '{ sec = 100, usec = 0 }\n' ;;
      *) exit 1 ;;
    esac
    ;;
  -w)
    value="${2#iogpu.wired_limit_mb=}"
    printf '%s\n' "$value" > "$FAKE_WIRED_FILE"
    ;;
  *) exit 1 ;;
esac
SYSCTL
write_stub "$tmp/bin/sudo" <<'SUDO'
[ "${1:-}" = -n ] && shift
"$@"
rc=$?
if [ -n "${SIGNAL_JOIN_PID:-}" ] && [ ! -e "$SIGNAL_SENT_FILE" ]; then
  : > "$SIGNAL_SENT_FILE"
  kill -TERM "$SIGNAL_JOIN_PID"
fi
exit "$rc"
SUDO
write_stub "$tmp/bin/vm-stat" <<'VMSTAT'
cat <<'OUT'
Mach Virtual Memory Statistics: (page size of 4096 bytes)
Pages free: 100000.
Pages inactive: 100000.
Pages speculative: 100000.
Pages wired down: 1000.
OUT
VMSTAT
write_stub "$tmp/bin/ssh" <<'SSH'
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
printf 'remote stdout\n'
printf 'remote stderr\n' >&2
rc="${FAKE_SSH_RC:-0}"
if [ -n "${FAKE_SSH_SEQUENCE:-}" ]; then
  n="$(cat "$FAKE_SSH_COUNT_FILE" 2>/dev/null || printf '0')"
  n=$((n + 1))
  printf '%s\n' "$n" > "$FAKE_SSH_COUNT_FILE"
  rc="$(sed -n "${n}p" "$FAKE_SSH_SEQUENCE")"
fi
exit "$rc"
SSH
chmod +x "$tmp/bin/"*

export PATH="$tmp/bin:$PATH"
export HOME="$tmp/home"
export CLUSTER_STATE_DIR="$tmp/state"
export CLUSTER_STATE_FILE="$tmp/state/link-state"
export CLUSTER_PEER_STATE_FILE="$tmp/state/local-peer-state.json"
export CLUSTER_LIFECYCLE_LOG="$tmp/lifecycle.log"
export CLUSTER_STATIC_SELF_IP=link-self
export CLUSTER_STATIC_PEER_IP=link-peer
export CLUSTER_PEER_STATE_PORT=11442
export CLUSTER_PEER_STATE_TIMEOUT_SECS=2
export CLUSTER_JOIN_TIMEOUT_SECS=20
export CLUSTER_HTTP_PORT=8000
export CLUSTER_ROLE=coordinator
export CLUSTER_RANK_LABEL=dev.test.rank
export CLUSTER_RANK_PROCESS_PATTERN=/fake-rank
export CLUSTER_RDMA_DEVICE=rdma_test
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_PD_RESERVE=5
export CLUSTER_IOCLASSCOUNT_BIN="$tmp/bin/ioclasscount"
export CLUSTER_IBV_DEVINFO_BIN="$tmp/bin/ibv-devinfo"
export CLUSTER_PGREP_BIN="$tmp/bin/pgrep"
export CLUSTER_CURL_BIN="$tmp/bin/curl"
export CLUSTER_LAUNCHCTL_BIN="$tmp/bin/launchctl"
export CLUSTER_SSH_BIN="$tmp/bin/ssh"
export CLUSTER_SW_VERS_BIN="$tmp/bin/sw-vers"
export CLUSTER_DARWIN_VERSION_BIN="$tmp/bin/darwin-version"
export CLUSTER_STAT_BIN="$tmp/bin/stat"
export CLUSTER_MODEL_STAT_BIN="$tmp/bin/model-stat"
export CLUSTER_SYSCTL_BIN="$tmp/bin/sysctl"
export CLUSTER_SED_BIN=sed
export CLUSTER_SUDO_BIN="$tmp/bin/sudo"
export CLUSTER_VMSTAT_BIN="$tmp/bin/vm-stat"
export CLUSTER_LAUNCH_AGENTS_DIR="$tmp/home/Library/LaunchAgents"
export CLUSTER_STANDALONE_WIRED_LIMIT_MB=1000
export CLUSTER_WIRED_LIMIT_MB=2000
export CLUSTER_COMPOSITOR_RESERVE_MB=100
export CLUSTER_SHARD_MEMORY_MB=128
export CLUSTER_MODEL=org/default
export CLUSTER_SHARDING_MODE=tensor
export HF_HOME="$tmp/hf"
export CLUSTER_SOFTWARE_JSON='{"nix_ai":"rev-a","mlx":"0.26","mlx_lm":"0.29","macos":"","model":"org/default","model_revision":""}'
export FAKE_PEER_STATE_FILE="$tmp/state/remote-peer-state.json"
export FAKE_LAUNCHCTL_LOG="$tmp/launchctl.log"
export FAKE_SSH_LOG="$tmp/ssh.log"
export FAKE_MTIME=99
export FAKE_NOW=1000
export FAKE_CONFIG_REV=config-a
export FAKE_PGREP_STATE=absent
export FAKE_HTTP_RC=0
export FAKE_WIRED_FILE="$tmp/wired-limit"
printf '1000\n' > "$FAKE_WIRED_FILE"
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$HF_HOME/hub/models--org--default/refs/main"
printf '{}\n' > "$HF_HOME/hub/models--org--default/snapshots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/config.json"
printf x > "$HF_HOME/hub/models--org--default/snapshots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/weights.safetensors"
printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' > "$HF_HOME/hub/models--user--override/refs/main"
printf '{}\n' > "$HF_HOME/hub/models--user--override/snapshots/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/config.json"
printf x > "$HF_HOME/hub/models--user--override/snapshots/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/weights.safetensors"

source modules/mlx/scripts/cluster-boot-scope.sh
source modules/mlx/scripts/cluster-peer-state-write.sh
source modules/mlx/scripts/cluster-peer-state.sh
source modules/mlx/scripts/cluster-link-locate.sh
source modules/mlx/scripts/cluster-link-repair.sh
source modules/mlx/scripts/cluster-rank-status.sh
source modules/mlx/scripts/cluster-rank-reap.sh
source modules/mlx/scripts/cluster-pd-count.sh
source modules/mlx/scripts/cluster-pd-gate.sh
source modules/mlx/scripts/cluster-room.sh
source modules/mlx/scripts/cluster-wired-limit.sh
source modules/mlx/scripts/cluster-serving-restore.sh
source modules/mlx/scripts/cluster-teardown.sh
source modules/mlx/scripts/cluster-join.sh
source modules/mlx/scripts/cluster-peer-state-serve.sh

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
date() {
  if [ "${1:-}" = +%s ]; then
    printf '%s\n' "$FAKE_NOW"
  elif [ "${1:-}" = -u ]; then
    printf '20261018T120000Z\n'
  else
    command date "$@"
  fi
}
sleep() {
  local duration="${1:-1}"
  command sleep 0.01
  FAKE_NOW=$((FAKE_NOW + duration))
  SECONDS=$((SECONDS + duration))
  if [ "${WITHDRAW_ON_SLEEP:-false}" = true ]; then
    local saved="$CLUSTER_PEER_STATE_FILE"
    CLUSTER_PEER_STATE_FILE="$FAKE_PEER_STATE_FILE"
    peer_state_write false 0 "$JOIN_SESSION_ID" abort
    CLUSTER_PEER_STATE_FILE="$saved"
    WITHDRAW_ON_SLEEP=false
  fi
  if [ "${FORM_WORKER_ON_SLEEP:-false}" = true ]; then
    local saved="$CLUSTER_PEER_STATE_FILE"
    CLUSTER_PEER_STATE_FILE="$FAKE_PEER_STATE_FILE"
    peer_state_write true "$JOIN_READY_AT" "$JOIN_SESSION_ID" formed "$JOIN_START_AT"
    CLUSTER_PEER_STATE_FILE="$saved"
    FORM_WORKER_ON_SLEEP=false
  fi
  if [ "${READY_WORKER_ON_SLEEP:-false}" = true ]; then
    local saved="$CLUSTER_PEER_STATE_FILE"
    CLUSTER_PEER_STATE_FILE="$FAKE_PEER_STATE_FILE"
    peer_state_write true 1000 "$JOIN_SESSION_ID" ready
    CLUSTER_PEER_STATE_FILE="$saved"
    READY_WORKER_ON_SLEEP=false
  fi
}
current_boot_epoch() { printf '100\n'; }
link_prep_ok() { return 0; }
write_state() {
  local file="$1" armed="$2" armed_at="$3" session="$4" phase="$5" start_at="${6:-0}"
  local saved="$CLUSTER_PEER_STATE_FILE"
  CLUSTER_PEER_STATE_FILE="$file"
  peer_state_write "$armed" "$armed_at" "$session" "$phase" "$start_at"
  local rc=$?
  CLUSTER_PEER_STATE_FILE="$saved"
  return "$rc"
}

echo 'the responder resets old and missing state, and preserves current-boot state:'
printf 'up\n' > "$CLUSTER_STATE_FILE"
printf '{"armed":true}\n' > "$CLUSTER_PEER_STATE_FILE"
if peer_state_reset_if_needed > "$tmp/reset-old.log"; then
  check 'old peer state is disarmed' false "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  check 'old peer state resets session phase' abort "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"
  check 'old peer state takes link down' down "$(cat "$CLUSTER_STATE_FILE")"
else
  echo '  FAIL old peer-state reset failed'; fail=1
fi
printf 'up\n' > "$CLUSTER_STATE_FILE"
printf '{"armed":true}\n' > "$CLUSTER_PEER_STATE_FILE"
FAKE_MTIME=100
if peer_state_reset_if_needed > "$tmp/reset-current.log"; then
  check 'current-boot state retained' true "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  check 'current-boot link state retained' up "$(cat "$CLUSTER_STATE_FILE")"
else
  echo '  FAIL current-boot state was reset'; fail=1
fi
rm -f "$CLUSTER_PEER_STATE_FILE"
if peer_state_reset_if_needed > "$tmp/reset-missing.log"; then
  check 'missing peer state recreated disarmed' false "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
else
  echo '  FAIL missing peer-state reset failed'; fail=1
fi
FAKE_MTIME=99

echo 'the writer publishes session, phase, and runtime configuration revision:'
JOIN_SESSION_ID=20261018T120000Z-0123abcd
JOIN_MODEL_ID=org/default
JOIN_MODEL_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export JOIN_SESSION_ID JOIN_MODEL_ID JOIN_MODEL_REVISION
if peer_state_write false 0 "$JOIN_SESSION_ID" preparing; then
  check 'preparing invalidates prior arm' false "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  check 'preparing session is recorded' "$JOIN_SESSION_ID" "$(jq -r '.session' "$CLUSTER_PEER_STATE_FILE")"
  check 'preparing phase is recorded' preparing "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"
  check 'writer configuration revision' config-a "$(jq -r '.configuration_revision' "$CLUSTER_PEER_STATE_FILE")"
  check 'writer publishes only the runtime version keys' '["macos","mlx","mlx_lm","model","model_revision","nix_ai"]' \
    "$(jq -c '.software | keys' "$CLUSTER_PEER_STATE_FILE")"
else
  echo '  FAIL preparing state write failed'; fail=1
fi
if peer_state_write true 1000 "$JOIN_SESSION_ID" ready; then
  check 'ready is armed' true "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  check 'ready model revision' "$JOIN_MODEL_REVISION" "$(jq -r '.software.model_revision' "$CLUSTER_PEER_STATE_FILE")"
else
  echo "  FAIL ready state write refused: ${PEER_GATE_REASON:-unknown}"; fail=1
fi

echo 'the peer accepts only a fresh matching session with known versions:'
FAKE_PEER_STATE_FILE="$tmp/state/remote-peer-state.json"
export FAKE_PEER_STATE_FILE
if write_state "$FAKE_PEER_STATE_FILE" true 995 "$JOIN_SESSION_ID" ready; then
  :
else
  echo '  FAIL could not create ready peer fixture'; fail=1
fi
if peer_armed_read; then
  check 'matching ready peer armed_at' 995 "$PEER_ARMED_AT"
else
  echo "  FAIL matching peer refused: $PEER_GATE_REASON"; fail=1
fi
old_session=20261018T120000Z-deadbeef
write_state "$FAKE_PEER_STATE_FILE" true 995 "$old_session" ready
if peer_armed_read; then
  echo '  FAIL stale prior session arm passed'; fail=1
else
  contains 'stale prior session is refused' peer-session-mismatch "$PEER_GATE_REASON"
fi
write_state "$FAKE_PEER_STATE_FILE" true 899 "$JOIN_SESSION_ID" ready
if peer_armed_read; then
  echo '  FAIL expired ready state passed'; fail=1
else
  contains 'expired ready state is refused' peer-arm-stale "$PEER_GATE_REASON"
fi
write_state "$FAKE_PEER_STATE_FILE" true 1010 "$JOIN_SESSION_ID" ready
if peer_armed_read; then
  echo '  FAIL future peer timestamp passed'; fail=1
else
  contains 'future peer timestamp is refused' peer-arm-future "$PEER_GATE_REASON"
fi

echo 'empty version values refuse even when both sides agree:'
old_software="$CLUSTER_SOFTWARE_JSON"
CLUSTER_SOFTWARE_JSON='{"nix_ai":"rev-a","mlx":"","mlx_lm":"0.29","macos":"","model":"org/default","model_revision":""}'
write_state "$FAKE_PEER_STATE_FILE" false 0 "$JOIN_SESSION_ID" preparing
jq '.armed = true | .armed_at = 995 | .phase = "ready" | .software.mlx = ""' \
  "$FAKE_PEER_STATE_FILE" > "$tmp/empty-version.json"
mv "$tmp/empty-version.json" "$FAKE_PEER_STATE_FILE"
if peer_armed_read; then
  echo '  FAIL matching empty version values passed'; fail=1
else
  contains 'matching empty mlx is unknown' 'version-unknown key=mlx' "$PEER_GATE_REASON"
fi
CLUSTER_SOFTWARE_JSON="$old_software"
FAKE_CONFIG_REV=unknown
if peer_armed_read; then
  echo '  FAIL unknown configuration revision passed'; fail=1
else
  contains 'unknown configuration revision is refused' 'version-unknown key=configuration_revision' "$PEER_GATE_REASON"
fi
FAKE_CONFIG_REV=config-a
write_state "$FAKE_PEER_STATE_FILE" true 995 "$JOIN_SESSION_ID" ready
jq '.software.nix_ai = "rev-b"' "$FAKE_PEER_STATE_FILE" > "$tmp/version-mismatch.json"
mv "$tmp/version-mismatch.json" "$FAKE_PEER_STATE_FILE"
if peer_armed_read; then
  echo '  FAIL version mismatch passed'; fail=1
else
  contains 'version mismatch identifies key' 'version-mismatch key=nix_ai' "$PEER_GATE_REASON"
fi
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1020
jq '.software.model = ""' "$FAKE_PEER_STATE_FILE" > "$tmp/peer-empty-version.json"
mv "$tmp/peer-empty-version.json" "$FAKE_PEER_STATE_FILE"
CLUSTER_ROLE=worker
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
if cluster_worker_wait_commit > "$tmp/peer-empty-version.log" 2>&1; then
  echo '  FAIL unknown peer version passed the commit wait'; fail=1
else
  contains 'unknown peer version refuses with its key' 'REFUSE reason=version-unknown detail=version-unknown key=model' \
    "$(cat "$tmp/peer-empty-version.log")"
fi

echo 'the coordinator commits only after the worker READY for the same session:'
CLUSTER_PEER_STATE_FILE="$tmp/state/local-peer-state.json"
CLUSTER_ROLE=coordinator
JOIN_READY_AT=1000
FAKE_NOW=1000
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
if cluster_join_wait_worker_ready && cluster_join_publish_commit; then
  check 'coordinator phase is commit' commit "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"
  check 'coordinator start_at is published' 1020 "$(jq -r '.start_at' "$CLUSTER_PEER_STATE_FILE")"
else
  echo "  FAIL coordinator commit refused: ${PEER_GATE_REASON:-unknown}"; fail=1
fi

echo 'the coordinator waits while the worker has not yet published its session:'
write_state "$FAKE_PEER_STATE_FILE" false 0 "" abort
# The fake worker join stays alive and publishes READY after the coordinator's first wait.
command sleep 30 &
CLUSTER_PEER_SSH_PID=$!
READY_WORKER_ON_SLEEP=true
if cluster_join_wait_worker_ready > "$tmp/late-worker.log" 2>&1; then
  contains 'late worker session is waited for' 'peer phase WAIT reason=peer-session-mismatch' "$(cat "$tmp/late-worker.log")"
else
  echo "  FAIL coordinator refused a worker that had not published yet: $(tail -1 "$tmp/late-worker.log")"; fail=1
fi
kill "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true
wait "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true
write_state "$FAKE_PEER_STATE_FILE" false 0 "" abort
true &
CLUSTER_PEER_SSH_PID=$!
wait "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true
if cluster_join_wait_worker_ready > "$tmp/exited-worker.log" 2>&1; then
  echo '  FAIL coordinator kept waiting after the worker join exited'; fail=1
else
  contains 'exited worker join refuses' 'REFUSE reason=peer-join-exited' "$(cat "$tmp/exited-worker.log")"
fi
CLUSTER_PEER_SSH_PID=""

echo 'an abort after worker READY becomes commit-withdrawn and launches nothing:'
CLUSTER_ROLE=worker
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
CLUSTER_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
write_state "$CLUSTER_PEER_STATE_FILE" false 0 "$JOIN_SESSION_ID" abort
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
: > "$FAKE_LAUNCHCTL_LOG"
if cluster_worker_wait_commit > "$tmp/abort.log" 2>&1; then
  echo '  FAIL worker accepted coordinator abort'; fail=1
else
  contains 'worker refuses with commit-withdrawn' 'REFUSE reason=commit-withdrawn' "$(cat "$tmp/abort.log")"
fi
check 'coordinator refusal issued no worker kickstart' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"

echo 'a worker reports formed only after coordinator formation is published:'
CLUSTER_ROLE=worker
CLUSTER_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
FAKE_PEER_STATE_FILE="$CLUSTER_PEER_STATE_FILE"
JOIN_START_AT=1000
write_state "$CLUSTER_PEER_STATE_FILE" false 0 "$JOIN_SESSION_ID" abort
if cluster_join_wait_coordinator_formed > "$tmp/coordinator-abort.log" 2>&1; then
  echo '  FAIL worker accepted coordinator abort during formation'; fail=1
else
  contains 'worker rejects coordinator abort during formation' \
    'REFUSE reason=coordinator-aborted' "$(cat "$tmp/coordinator-abort.log")"
fi
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" formed 1000
if cluster_join_wait_coordinator_formed; then
  echo '  ok   worker accepts coordinator formed for the matching session'
else
  echo "  FAIL coordinator formed was refused: ${PEER_GATE_REASON:-unknown}"; fail=1
fi
if jq '.formed_at = 984' "$CLUSTER_PEER_STATE_FILE" > "$tmp/stale-formed.json"; then
  mv "$tmp/stale-formed.json" "$CLUSTER_PEER_STATE_FILE"
fi
FAKE_NOW=1000
if cluster_join_wait_coordinator_formed > "$tmp/stale-formed.log" 2>&1; then
  echo '  FAIL stale coordinator formed timestamp passed'; fail=1
else
  contains 'stale coordinator formation is refused' 'REFUSE reason=coordinator-formed-stale' \
    "$(cat "$tmp/stale-formed.log")"
fi

echo 'the coordinator refreshes formed_at while waiting for worker formation:'
CLUSTER_ROLE=coordinator
CLUSTER_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
JOIN_READY_AT=1000
JOIN_START_AT=1000
FAKE_NOW=1000
SECONDS=0
FAKE_PGREP_STATE=running
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" formed 1000
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
FORM_WORKER_ON_SLEEP=true
if cluster_join_maintain_formed; then
  check 'coordinator observes worker formed' formed "$(jq -r '.phase' "$FAKE_PEER_STATE_FILE")"
  check 'coordinator refreshes heartbeat after 5s' 1005 "$(jq -r '.formed_at' "$CLUSTER_PEER_STATE_FILE")"
else
  echo '  FAIL coordinator did not maintain the formed heartbeat'; fail=1
fi
CLUSTER_ROLE=worker
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"

echo 'a withdrawn COMMIT between sleep and kickstart is re-read and refused:'
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
CLUSTER_PEER_STATE_FILE="$FAKE_PEER_STATE_FILE"
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1002
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
JOIN_START_AT=1002
JOIN_SHARDING=tensor
FAKE_NOW=1000
WITHDRAW_ON_SLEEP=true
: > "$FAKE_LAUNCHCTL_LOG"
if cluster_final_rank_start 1002 > "$tmp/withdrawn-commit.log" 2>&1; then
  echo '  FAIL withdrawn commit reached kickstart'; fail=1
else
  contains 'withdrawn commit is refused' 'REFUSE reason=commit-withdrawn' "$(cat "$tmp/withdrawn-commit.log")"
fi
check 'withdrawn commit issued no kickstart' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"

echo 'worker accepts a COMMIT up to 2s after start_at and publishes STARTED:'
CLUSTER_ROLE=worker
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
JOIN_READY_AT=1000
JOIN_START_AT=1000
JOIN_SHARDING=tensor
FAKE_NOW=1001
SECONDS=0
FAKE_PGREP_STATE=running
FAKE_KICKSTART_RC=0
export FAKE_KICKSTART_RC CLUSTER_LIFECYCLE_COMPONENT=cluster-join
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1000
: > "$FAKE_LAUNCHCTL_LOG"
if cluster_final_rank_start 1000; then
  check 'worker late by 1s publishes started' started "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"
  check 'worker started session is preserved' "$JOIN_SESSION_ID" "$(jq -r '.session' "$CLUSTER_PEER_STATE_FILE")"
  check 'worker started boundary is preserved' 1000 "$(jq -r '.start_at' "$CLUSTER_PEER_STATE_FILE")"
  check 'worker kickstart was issued once' 1 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"
else
  echo '  FAIL worker refused the 1s start delay'; fail=1
fi

echo 'worker refuses a kickstart whose process is not visible within 5s:'
FAKE_NOW=1000
SECONDS=0
FAKE_KICKSTART_RC=0
for _ in {1..20}; do printf 'absent\n'; done > "$tmp/no-rank.sequence"
export FAKE_PGREP_SEQUENCE="$tmp/no-rank.sequence"
export FAKE_PGREP_COUNT_FILE="$tmp/no-rank-count"
: > "$FAKE_PGREP_COUNT_FILE"
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1000
: > "$FAKE_LAUNCHCTL_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
if (
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  JOIN_REBOOT=0
  CLUSTER_PEER_SSH_PID=
  formed=false
  quiesced=false
  ceiling_attempted=false
  cluster_lifecycle_log_start
  cluster_lifecycle_lock_acquire || exit 2
  trap cluster_join_exit EXIT
  cluster_final_rank_start 1000 || exit 1
) > "$tmp/worker-process-check.log" 2>&1; then
  echo '  FAIL worker without a process passed'; fail=1
else
  check 'worker process check failure exits nonzero' 1 "$?"
fi
contains 'worker process check failure is logged' 'REFUSE reason=worker-rank-not-running' \
  "$(cat "$CLUSTER_LIFECYCLE_LOG")"
check 'worker process check failure publishes abort' abort "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"
check 'process-check failure follows the kickstart attempt' 1 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"
if grep -q 'phase=started' "$CLUSTER_LIFECYCLE_LOG"; then
  echo '  FAIL process-check failure published STARTED'; fail=1
else
  echo '  ok   process-check failure never publishes STARTED'
fi
unset FAKE_PGREP_SEQUENCE FAKE_PGREP_COUNT_FILE

echo 'worker 3s late refuses and its exit teardown publishes abort:'
FAKE_NOW=1003
SECONDS=0
FAKE_PGREP_STATE=absent
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1000
: > "$FAKE_LAUNCHCTL_LOG"
if (
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  JOIN_REBOOT=0
  CLUSTER_PEER_SSH_PID=
  formed=false
  quiesced=false
  ceiling_attempted=false
  cluster_lifecycle_log_start
  cluster_lifecycle_lock_acquire || exit 2
  trap cluster_join_exit EXIT
  cluster_final_rank_start 1000 || exit 1
) > "$tmp/late-worker.log" 2>&1; then
  echo '  FAIL worker accepted the 3s start delay'; fail=1
else
  check 'worker 3s late exits nonzero' 1 "$?"
fi
contains 'worker 3s late reports missed-start-window' 'REFUSE reason=missed-start-window' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
check 'late worker teardown publishes abort' abort "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"
check 'late worker issued no kickstart' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"

echo 'coordinator waits for worker STARTED before any kickstart:'
CLUSTER_ROLE=coordinator
CLUSTER_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
FAKE_NOW=1000
SECONDS=0
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1000
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
: > "$FAKE_LAUNCHCTL_LOG"
if cluster_final_rank_start 1000 > "$tmp/no-started.log" 2>&1; then
  echo '  FAIL coordinator passed without worker STARTED'; fail=1
else
  contains 'missing worker STARTED times out' 'REFUSE reason=worker-start-timeout' "$(cat "$tmp/no-started.log")"
fi
check 'coordinator issued no kickstart without STARTED' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"

echo 'worker kickstart failure aborts the session and makes coordinator detach the worker:'
CLUSTER_ROLE=worker
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
FAKE_NOW=1000
SECONDS=0
FAKE_KICKSTART_RC=1
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" ready
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1000
: > "$FAKE_LAUNCHCTL_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
if (
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  JOIN_REBOOT=0
  CLUSTER_PEER_SSH_PID=
  formed=false
  quiesced=false
  ceiling_attempted=false
  cluster_lifecycle_log_start
  cluster_lifecycle_lock_acquire || exit 2
  trap cluster_join_exit EXIT
  cluster_final_rank_start 1000 || exit 1
) > "$tmp/worker-kickstart-failure.log" 2>&1; then
  echo '  FAIL worker kickstart failure returned success'; fail=1
else
  check 'worker kickstart failure exits nonzero' 1 "$?"
fi
check 'worker kickstart failure publishes abort' abort "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"

CLUSTER_ROLE=coordinator
CLUSTER_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
CLUSTER_PEER_SSH=user@worker
CLUSTER_JOIN_TIMEOUT_SECS=20
FAKE_KICKSTART_RC=0
FAKE_NOW=1000
SECONDS=0
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1000
unset FAKE_SSH_SEQUENCE FAKE_SSH_COUNT_FILE
FAKE_SSH_RC=1
export FAKE_SSH_RC
: > "$FAKE_SSH_LOG"
: > "$FAKE_LAUNCHCTL_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
if (
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  JOIN_REBOOT=0
  CLUSTER_PEER_SSH_PID=
  JOIN_MODEL_EXPLICIT=false
  formed=false
  quiesced=false
  ceiling_attempted=false
  cluster_lifecycle_log_start
  cluster_lifecycle_lock_acquire || exit 2
  cluster_peer_ssh_start || exit 2
  trap cluster_join_exit EXIT
  cluster_final_rank_start 1000 || exit 1
) > "$tmp/coordinator-worker-abort.log" 2>&1; then
  echo '  FAIL coordinator proceeded after worker abort'; fail=1
else
  check 'coordinator abort exits nonzero' 1 "$?"
fi
check 'coordinator teardown publishes abort' abort "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"
check 'coordinator issued no kickstart after worker failure' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"
contains 'coordinator failure invokes session-scoped remote detach' \
  'user@worker cluster-detach --worker --session 20261018T120000Z-0123abcd' "$(cat "$FAKE_SSH_LOG")"
contains 'coordinator records worker abort' 'REFUSE reason=worker-aborted' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
unset FAKE_SSH_SEQUENCE FAKE_SSH_COUNT_FILE
FAKE_SSH_RC=0
export FAKE_SSH_RC
CLUSTER_ROLE=worker
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
CLUSTER_PEER_SSH=

echo 'the coordinator refuses a late kickstart but accepts start_at+10:'
CLUSTER_ROLE=coordinator
CLUSTER_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
JOIN_READY_AT=1000
JOIN_START_AT=1000
JOIN_SHARDING=tensor
FAKE_PGREP_STATE=running
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1000
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" started 1000
SECONDS=0
FAKE_NOW=1011
: > "$FAKE_LAUNCHCTL_LOG"
if cluster_final_rank_start 1000 > "$tmp/coordinator-late.log" 2>&1; then
  coordinator_late_rc=0
else
  coordinator_late_rc=$?
fi
if [ "$coordinator_late_rc" -eq 1 ] &&
  grep -q 'REFUSE reason=missed-start-window' "$tmp/coordinator-late.log" &&
  ! grep -q 'kickstart' "$FAKE_LAUNCHCTL_LOG"; then
  echo '  ok   coordinator late start returns 1 without kickstart'
else
  echo '  FAIL coordinator late start did not return 1 before kickstart'; fail=1
fi

FAKE_NOW=1010
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" commit 1000
: > "$FAKE_LAUNCHCTL_LOG"
if cluster_final_rank_start 1000 > "$tmp/coordinator-boundary.log" 2>&1; then
  if [ "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)" -eq 1 ]; then
    echo '  ok   coordinator kickstarts at start_at+10'
  else
    echo '  FAIL coordinator exact boundary did not kickstart once'; fail=1
  fi
  check 'coordinator publishes started after kickstart' started "$(jq -r '.phase' "$CLUSTER_PEER_STATE_FILE")"
else
  echo '  FAIL coordinator exact start window boundary refused'; fail=1
fi

echo 'worker lease expiry follows coordinator timestamps and phase:'
CLUSTER_ROLE=worker
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
FAKE_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
CLUSTER_COORDINATOR_LEASE_SECS=2
FAKE_NOW=2000
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" started 1000
COORDINATOR_LEASE_TS=
COORDINATOR_LEASE_SEEN=0
SECONDS=0
if cluster_join_coordinator_lease_ok > "$tmp/lease-expiry.log" 2>&1; then
  SECONDS=$((COORDINATOR_LEASE_SEEN + 3))
  if cluster_join_coordinator_lease_ok >> "$tmp/lease-expiry.log" 2>&1; then
    lease_expiry_rc=0
  else
    lease_expiry_rc=$?
  fi
  if [ "$lease_expiry_rc" -eq 1 ] &&
    grep -q 'reason=coordinator-lease-expired' "$tmp/lease-expiry.log"; then
    echo '  ok   unchanged coordinator timestamp expires the lease with rc=1'
  else
    echo '  FAIL unchanged coordinator timestamp did not expire the lease'; fail=1
  fi
else
  echo '  FAIL coordinator lease refused before expiry'; fail=1
fi

FAKE_NOW=2100
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" started 1000
COORDINATOR_LEASE_TS=
COORDINATOR_LEASE_SEEN=0
SECONDS=0
if cluster_join_coordinator_lease_ok; then
  FAKE_NOW=2101
  write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" started 1000
  SECONDS=2
  if cluster_join_coordinator_lease_ok; then
    FAKE_NOW=2102
    write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" started 1000
    SECONDS=4
    if cluster_join_coordinator_lease_ok; then
      SECONDS=5
      if cluster_join_coordinator_lease_ok; then
        echo '  ok   advancing coordinator timestamps keep the lease alive past its window'
      else
        echo '  FAIL fresh coordinator timestamp did not keep the lease alive'; fail=1
      fi
    else
      echo '  FAIL second coordinator timestamp refresh was refused'; fail=1
    fi
  else
    echo '  FAIL first coordinator timestamp refresh was refused'; fail=1
  fi
else
  echo '  FAIL coordinator lease refused before its timestamp refreshes'; fail=1
fi

FAKE_NOW=2200
write_state "$FAKE_PEER_STATE_FILE" false 0 "$JOIN_SESSION_ID" abort
COORDINATOR_LEASE_TS=
COORDINATOR_LEASE_SEEN=0
: > "$tmp/lease-abort.log"
if cluster_join_coordinator_lease_ok > "$tmp/lease-abort.log" 2>&1; then
  coordinator_abort_rc=0
else
  coordinator_abort_rc=$?
fi
if [ "$coordinator_abort_rc" -eq 1 ] && grep -q 'reason=coordinator-aborted' "$tmp/lease-abort.log"; then
  echo '  ok   worker refuses coordinator abort with rc=1'
else
  echo '  FAIL worker abort did not return 1 with the expected reason'; fail=1
fi

FAKE_NOW=2300
write_state "$FAKE_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" started 1000
COORDINATOR_LEASE_TS=
COORDINATOR_LEASE_SEEN=0
SECONDS=0
if cluster_join_coordinator_lease_ok; then
  rm -f "$FAKE_PEER_STATE_FILE"
  SECONDS=$((COORDINATOR_LEASE_SEEN + 3))
  if cluster_join_coordinator_lease_ok > "$tmp/lease-unreachable.log" 2>&1; then
    unreachable_lease_rc=0
  else
    unreachable_lease_rc=$?
  fi
  if [ "$unreachable_lease_rc" -eq 1 ] && grep -q 'reason=coordinator-lease-expired' "$tmp/lease-unreachable.log"; then
    echo '  ok   unreachable coordinator state expires the lease with rc=1'
  else
    echo '  FAIL unreachable coordinator did not return 1 for lease expiry'; fail=1
  fi
else
  echo '  FAIL coordinator lease refused before the fetch failure'; fail=1
fi
unset CLUSTER_COORDINATOR_LEASE_SECS

echo 'room refuses missing shard size and the session id is required for workers:'
unset CLUSTER_SHARD_MEMORY_MB
if rank_start_room_ok; then
  echo '  FAIL missing shard size passed'; fail=1
else
  contains 'missing shard size sets room-unconfigured' room-unconfigured "$MEM_HEADROOM_DETAIL"
fi
CLUSTER_SHARD_MEMORY_MB=128
: > "$CLUSTER_LIFECYCLE_LOG"
if (cluster_join_main --worker) > /dev/null 2>&1; then
  echo '  FAIL worker without session passed'; fail=1
else
  check 'worker without session exits nonzero' 1 "$?"
fi
contains 'missing worker session is logged' 'REFUSE reason=no-session' "$(cat "$CLUSTER_LIFECYCLE_LOG")"

echo 'a coordinator requires both HTTP readiness and a live rank:'
CLUSTER_ROLE=coordinator
CLUSTER_HTTP_PORT=8000
CLUSTER_JOIN_TIMEOUT_SECS=1
FAKE_HTTP_RC=0
FAKE_PGREP_STATE=absent
SECONDS=0
if cluster_join_wait_coordinator_formed_local > "$tmp/no-rank-formed.log" 2>&1; then
  echo '  FAIL coordinator formed without a live rank'; fail=1
else
  contains 'HTTP success without a rank is refused' 'REFUSE reason=coordinator-endpoint-not-formed' "$(cat "$tmp/no-rank-formed.log")"
fi
FAKE_PGREP_STATE=running
if cluster_join_wait_coordinator_formed_local; then
  echo '  ok   coordinator HTTP plus live rank passes'
else
  echo '  FAIL coordinator HTTP plus live rank refused'; fail=1
fi
FAKE_PGREP_SEQUENCE="$tmp/pgrep.sequence"
FAKE_PGREP_COUNT_FILE="$tmp/pgrep.count"
printf 'running\nabsent\n' > "$FAKE_PGREP_SEQUENCE"
export FAKE_PGREP_SEQUENCE FAKE_PGREP_COUNT_FILE
JOIN_READY_AT=1000
FAKE_NOW=1000
if cluster_join_publish_formed > "$tmp/rank-exit-formed.log" 2>&1; then
  echo '  FAIL rank exit during formed publication passed'; fail=1
else
  contains 'formed publication rechecks rank' 'REFUSE reason=rank-not-running-at-formation' "$(cat "$tmp/rank-exit-formed.log")"
fi
unset FAKE_PGREP_SEQUENCE FAKE_PGREP_COUNT_FILE

echo 'the coordinator sends the worker its session and SSH reap has a hard deadline:'
CLUSTER_ROLE=coordinator
CLUSTER_PEER_SSH=user@peer
CLUSTER_JOIN_TIMEOUT_SECS=20
JOIN_SESSION_ID=20261018T120000Z-0123abcd
export CLUSTER_PEER_SSH
unset -f sleep
: > "$FAKE_SSH_LOG"
cluster_peer_ssh_start
cluster_peer_ssh_wait || { echo '  FAIL short worker ssh did not reap'; fail=1; }
contains 'worker ssh includes the session id' \
  'user@peer cluster-join --worker --session 20261018T120000Z-0123abcd' "$(cat "$FAKE_SSH_LOG")"
: > "$FAKE_SSH_LOG"
FAKE_SSH_RC=0
export FAKE_SSH_RC
if cluster_peer_remote_detach; then
  contains 'coordinator requests a session-scoped remote detach' \
    'user@peer cluster-detach --worker --session 20261018T120000Z-0123abcd' "$(cat "$FAKE_SSH_LOG")"
else
  echo '  FAIL session-scoped remote detach was not acknowledged'; fail=1
fi
: > "$FAKE_SSH_LOG"
FAKE_SSH_RC=255
if cluster_peer_remote_detach > "$tmp/remote-detach-failure.log" 2>&1; then
  echo '  FAIL remote detach transport failure was acknowledged'; fail=1
else
  contains 'unconfirmed remote cleanup is refused' 'REFUSE reason=peer-cleanup-unconfirmed' \
    "$(cat "$tmp/remote-detach-failure.log")"
fi
FAKE_SSH_RC=0
: > "$FAKE_SSH_LOG"
printf '255\n0\n' > "$tmp/ssh-results"
export FAKE_SSH_SEQUENCE="$tmp/ssh-results"
export FAKE_SSH_COUNT_FILE="$tmp/ssh-count"
: > "$FAKE_SSH_COUNT_FILE"
: > "$CLUSTER_LIFECYCLE_LOG"
if (
  cluster_lifecycle_log_start
  cluster_lifecycle_lock_acquire || exit 2
  FAKE_PGREP_STATE=absent
  JOIN_SESSION_ID=20261018T120000Z-0123abcd
  JOIN_MODEL_EXPLICIT=false
  CLUSTER_PEER_SSH_PID=
  CLUSTER_PEER_SSH_RC=0
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  formed=false
  ceiling_attempted=true
  quiesced=false
  cluster_peer_ssh_start || exit 2
  set +e
  false
  cluster_join_exit
) > /dev/null 2>&1; then
  echo '  FAIL coordinator peer failure was reported as success'; fail=1
else
  check 'coordinator peer failure exits nonzero' 1 "$?"
fi
contains 'coordinator failure invokes session-scoped worker cleanup' \
  'user@peer cluster-detach --worker --session 20261018T120000Z-0123abcd' "$(cat "$FAKE_SSH_LOG")"
contains 'coordinator logs remote cleanup acknowledgment' 'worker detach acknowledged session=20261018T120000Z-0123abcd' \
  "$(cat "$CLUSTER_LIFECYCLE_LOG")"
unset FAKE_SSH_SEQUENCE FAKE_SSH_COUNT_FILE
: > "$CLUSTER_LIFECYCLE_LOG"
if (
  CLUSTER_JOIN_TIMEOUT_SECS=0
  cluster_lifecycle_log_start
  kill() { return 0; }
  sleep() { SECONDS=$((SECONDS + 1)); }
  command sleep 60 &
  CLUSTER_PEER_SSH_PID=$!
  if cluster_peer_ssh_wait; then exit 0; else rc=$?; fi
  builtin kill -KILL "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true
  wait "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true
  exit "$rc"
) > /dev/null 2>&1; then
  echo '  FAIL unreaped ssh uncertainty passed'; fail=1
else
  contains 'ssh reap uncertainty is a refusal' 'REFUSE reason=peer-ssh-reap-uncertain' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
fi

echo 'lifecycle lock recovery reclaims dead, previous-boot, and aged ownerless locks:'
lock="$CLUSTER_STATE_DIR/cluster-lifecycle.lock"
FAKE_NOW=1000
FAKE_MTIME=99
mkdir -p "$lock"
printf '99999999\n' > "$lock/pid"
printf '100\n' > "$lock/boot"
if cluster_lifecycle_lock_acquire > "$tmp/dead-lock.log" 2>&1; then
  contains 'dead pid lock is reclaimed' 'lifecycle-lock reclaimed reason=dead-pid' "$(cat "$tmp/dead-lock.log")"
  cluster_lifecycle_lock_release
else
  echo '  FAIL dead pid lock was not reclaimed'; fail=1
fi

mkdir -p "$lock"
printf '%s\n' "$$" > "$lock/pid"
printf '99\n' > "$lock/boot"
if cluster_lifecycle_lock_acquire > "$tmp/other-boot-lock.log" 2>&1; then
  contains 'other boot lock is reclaimed' 'lifecycle-lock reclaimed reason=other-boot' \
    "$(cat "$tmp/other-boot-lock.log")"
  cluster_lifecycle_lock_release
else
  echo '  FAIL previous-boot lock was not reclaimed'; fail=1
fi

mkdir -p "$lock"
printf '100\n' > "$lock/boot"
FAKE_MTIME=900
if cluster_lifecycle_lock_acquire > "$tmp/ownerless-lock.log" 2>&1; then
  contains 'aged ownerless lock is reclaimed' 'lifecycle-lock reclaimed reason=ownerless' \
    "$(cat "$tmp/ownerless-lock.log")"
  cluster_lifecycle_lock_release
else
  echo '  FAIL aged ownerless lock was not reclaimed'; fail=1
fi

mkdir -p "$lock"
printf '%s\n' "$$" > "$lock/pid"
printf '100\n' > "$lock/boot"
FAKE_MTIME=900
if cluster_lifecycle_lock_acquire > "$tmp/live-lock.log" 2>&1; then
  echo '  FAIL live same-boot owner was reclaimed'; fail=1
  cluster_lifecycle_lock_release
else
  check 'live same-boot owner still refuses' 1 "$?"
fi
check 'live lock owner remains recorded' "$$" "$(cat "$lock/pid")"
rm -rf "$lock"

echo 'a second lifecycle command refuses before gates when the lock is held:'
CLUSTER_LIFECYCLE_COMPONENT=cluster-join
cluster_lifecycle_lock_acquire
: > "$CLUSTER_LIFECYCLE_LOG"
if (cluster_join_main) > /dev/null 2>&1; then
  echo '  FAIL overlapping join passed'; fail=1
else
  check 'overlapping join exits nonzero' 1 "$?"
fi
contains 'overlapping join reports the lock' 'REFUSE reason=lifecycle-locked' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
cluster_lifecycle_lock_release

echo 'a signal between J3 and J4 restores the wired ceiling:'
CLUSTER_ROLE=coordinator
CLUSTER_PEER_SSH=
CLUSTER_JOIN_TIMEOUT_SECS=20
FAKE_PGREP_STATE=absent
FAKE_NOW=1000
printf '1000\n' > "$FAKE_WIRED_FILE"
rm -f "$tmp/signal-sent"
: > "$CLUSTER_LIFECYCLE_LOG"
set +e
(
  SIGNAL_JOIN_PID="$BASHPID"
  SIGNAL_SENT_FILE="$tmp/signal-sent"
  export SIGNAL_JOIN_PID SIGNAL_SENT_FILE
  cluster_join_main
) > /dev/null 2>&1
join_rc=$?
set -e
check 'J3 TERM preserves signal result' 143 "$join_rc"
check 'ceiling restored after J3 signal' 1000 "$(cat "$FAKE_WIRED_FILE")"
check 'link is down after J3 recovery' down "$(cat "$CLUSTER_STATE_FILE")"
contains 'J3 was attempted before recovery' 'cluster-join: J3 wired-ceiling' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
if grep -q 'cluster-join: J4 quiesce' "$CLUSTER_LIFECYCLE_LOG"; then
  echo '  FAIL signal was delivered after J4'; fail=1
else
  echo '  ok   signal was delivered between J3 and J4'
fi

echo 'model selection retains its cached-model override contract:'
CLUSTER_MODEL=org/default
CLUSTER_SHARDING_MODE=tensor
CLUSTER_WIRED_LIMIT_MB=2000
CLUSTER_COMPOSITOR_RESERVE_MB=100
export FAKE_MODEL_SIZE=20971520
if cluster_join_model_select user/override true true; then
  check 'model override id selected' user/override "$JOIN_MODEL_ID"
  check 'model override revision selected' bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$JOIN_MODEL_REVISION"
  check 'explicit shard size computed' 11 "$JOIN_SHARD_MEMORY_MB"
  check 'pipeline sharding selected' pipeline "$JOIN_SHARDING"
else
  echo '  FAIL cached model override refused'; fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo 'join handshake checks FAILED' >&2
  exit 1
fi
echo 'join handshake checks passed'
