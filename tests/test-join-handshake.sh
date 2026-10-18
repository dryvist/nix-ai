#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state" "$tmp/hf/hub/models--org--default/refs" \
  "$tmp/hf/hub/models--org--default/snapshots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
  "$tmp/hf/hub/models--user--override/refs" \
  "$tmp/hf/hub/models--user--override/snapshots/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
case "$*" in
  *"http://$CLUSTER_STATIC_PEER_IP:"*)
    [ -f "$FAKE_PEER_STATE_FILE" ] || exit 7
    cat "$FAKE_PEER_STATE_FILE"
    ;;
  *http://127.0.0.1:*) exit "${FAKE_HTTP_RC:-7}" ;;
  *) exit 1 ;;
esac
CURL
cat > "$tmp/bin/launchctl" <<'LAUNCHCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_LOG"
if [ "${1:-}" = print ]; then printf 'state = running\n'; fi
exit "${FAKE_LAUNCHCTL_RC:-0}"
LAUNCHCTL
cat > "$tmp/bin/stat" <<'STAT'
#!/usr/bin/env bash
printf '%s\n' "$FAKE_MTIME"
STAT
cat > "$tmp/bin/sw-vers" <<'SWVERS'
#!/usr/bin/env bash
printf 'build-a\n'
SWVERS
cat > "$tmp/bin/darwin-version" <<'DARWINVERSION'
#!/usr/bin/env bash
printf '{"configurationRevision":"%s"}\n' "${FAKE_CONFIG_REV:-config-a}"
DARWINVERSION
cat > "$tmp/bin/model-stat" <<'MODELSTAT'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_MODEL_SIZE:-1}"
MODELSTAT
cat > "$tmp/bin/pgrep" <<'PGREP'
#!/usr/bin/env bash
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
cat > "$tmp/bin/ibv-devinfo" <<'IBV'
#!/usr/bin/env bash
printf 'hca_id: rdma_test\nmax_pd: 11\n'
IBV
cat > "$tmp/bin/ioclasscount" <<'IOCLASS'
#!/usr/bin/env bash
printf '%s = %s\n' "$1" "${FAKE_PD_HELD:-0}"
IOCLASS
cat > "$tmp/bin/sysctl" <<'SYSCTL'
#!/usr/bin/env bash
case "${1:-}" in
  -n)
    case "${2:-}" in
      vm.swapusage) printf 'vm.swapusage: total = 0M used = 0M free = 1M\n' ;;
      iogpu.wired_limit_mb) cat "$FAKE_WIRED_FILE" ;;
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
cat > "$tmp/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
[ "${1:-}" = -n ] && shift
"$@"
rc=$?
if [ -n "${SIGNAL_JOIN_PID:-}" ] && [ ! -e "$SIGNAL_SENT_FILE" ]; then
  : > "$SIGNAL_SENT_FILE"
  /bin/kill -TERM "$SIGNAL_JOIN_PID"
fi
exit "$rc"
SUDO
cat > "$tmp/bin/vm-stat" <<'VMSTAT'
#!/usr/bin/env bash
cat <<'OUT'
Mach Virtual Memory Statistics: (page size of 4096 bytes)
Pages free: 100000.
Pages inactive: 100000.
Pages speculative: 100000.
Pages wired down: 1000.
OUT
VMSTAT
cat > "$tmp/bin/ssh" <<'SSH'
#!/usr/bin/env bash
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
  FAKE_NOW=$((FAKE_NOW + duration))
  SECONDS=$((SECONDS + duration))
  if [ "${WITHDRAW_ON_SLEEP:-false}" = true ]; then
    local saved="$CLUSTER_PEER_STATE_FILE"
    CLUSTER_PEER_STATE_FILE="$FAKE_PEER_STATE_FILE"
    peer_state_write false 0 "$JOIN_SESSION_ID" abort
    CLUSTER_PEER_STATE_FILE="$saved"
    WITHDRAW_ON_SLEEP=false
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
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"
CLUSTER_PEER_STATE_FILE="$tmp/state/coordinator-peer-state.json"
write_state "$CLUSTER_PEER_STATE_FILE" false 0 "$JOIN_SESSION_ID" abort
FAKE_PEER_STATE_FILE="$CLUSTER_PEER_STATE_FILE"
if cluster_join_wait_coordinator_formed > "$tmp/coordinator-abort.log" 2>&1; then
  echo '  FAIL worker accepted coordinator abort during formation'; fail=1
else
  contains 'worker rejects coordinator abort during formation' \
    'REFUSE reason=coordinator-aborted' "$(cat "$tmp/coordinator-abort.log")"
fi
write_state "$CLUSTER_PEER_STATE_FILE" true 1000 "$JOIN_SESSION_ID" formed
if cluster_join_wait_coordinator_formed; then
  echo '  ok   worker accepts coordinator formed for the matching session'
else
  echo "  FAIL coordinator formed was refused: ${PEER_GATE_REASON:-unknown}"; fail=1
fi
CLUSTER_PEER_STATE_FILE="$tmp/state/worker-peer-state.json"

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
  export CLUSTER_LIFECYCLE_COMPONENT=cluster-join
  cluster_lifecycle_log_start
  cluster_lifecycle_lock_acquire || exit 2
  FAKE_PGREP_STATE=absent
  JOIN_SESSION_ID=20261018T120000Z-0123abcd
  JOIN_MODEL_EXPLICIT=false
  CLUSTER_PEER_SSH_PID=
  CLUSTER_PEER_SSH_RC=0
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  JOIN_IGNORE_SIGNAL=false
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
  /bin/sleep 60 &
  CLUSTER_PEER_SSH_PID=$!
  if cluster_peer_ssh_wait; then exit 0; else rc=$?; fi
  /bin/kill -KILL "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true
  wait "$CLUSTER_PEER_SSH_PID" 2> /dev/null || true
  exit "$rc"
) > /dev/null 2>&1; then
  echo '  FAIL unreaped ssh uncertainty passed'; fail=1
else
  contains 'ssh reap uncertainty is a refusal' 'REFUSE reason=peer-ssh-reap-uncertain' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
fi

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
