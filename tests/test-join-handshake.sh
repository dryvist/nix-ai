#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"
export CLUSTER_STATE_DIR="$tmp/state"
export HF_HOME="$tmp/hf"
export CLUSTER_MODEL=org/default
export CLUSTER_SHARDING_MODE=tensor
export CLUSTER_SHARD_MEMORY_MB=128
export CLUSTER_WIRED_LIMIT_MB=2000
export CLUSTER_COMPOSITOR_RESERVE_MB=100

cat > "$tmp/bin/sw-vers" <<'SWVERS'
#!/usr/bin/env bash
printf 'build-a\n'
SWVERS
cat > "$tmp/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
[ -z "${FAKE_SSH_PID_FILE:-}" ] || printf '%s\n' "$$" > "$FAKE_SSH_PID_FILE"
printf 'remote stdout\n'
printf 'remote stderr\n' >&2
[ -n "${FAKE_SSH_SLEEP:-}" ] && exec /bin/sleep "$FAKE_SSH_SLEEP"
exit "${FAKE_SSH_RC:-0}"
SSH
cat > "$tmp/bin/launchctl" <<'LAUNCHCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_LOG"
[ "${1:-}" = print ] && printf 'state = running\n'
LAUNCHCTL
cat > "$tmp/bin/stat" <<'STAT'
#!/usr/bin/env bash
printf '%s\n' "$FAKE_MTIME"
STAT
cat > "$tmp/bin/model-stat" <<'MODELSTAT'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_MODEL_SIZE:-1}"
MODELSTAT
chmod +x "$tmp/bin/sw-vers" "$tmp/bin/ssh" "$tmp/bin/launchctl" "$tmp/bin/stat" "$tmp/bin/model-stat"

source modules/mlx/scripts/cluster-boot-scope.sh
source modules/mlx/scripts/cluster-peer-state-write.sh
source modules/mlx/scripts/cluster-peer-state.sh
source modules/mlx/scripts/cluster-join.sh
source modules/mlx/scripts/cluster-peer-state-serve.sh
source modules/mlx/scripts/cluster-teardown.sh

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
make_cached_model() {
  local model="$1" revision="$2" org repo cache snapshot
  org="${model%%/*}"
  repo="${model#*/}"
  cache="$HF_HOME/hub/models--$org--$repo"
  snapshot="$cache/snapshots/$revision"
  mkdir -p "$cache/refs" "$snapshot"
  printf '%s\n' "$revision" > "$cache/refs/main"
  printf '{}\n' > "$snapshot/config.json"
  printf x > "$snapshot/weights.safetensors"
}

date() {
  if [ "${1:-}" = +%s ]; then
    printf '%s\n' "$FAKE_NOW"
  else
    command date "$@"
  fi
}
current_boot_epoch() { printf '100\n'; }
generation_local_rev() { printf 'gen-a\n'; }
export CLUSTER_PEER_STATE_FILE="$tmp/state/peer-state.json"
export CLUSTER_STATE_FILE="$tmp/state/link-state"
model_revision_default=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export CLUSTER_SOFTWARE_JSON="{\"nix_ai\":\"rev-a\",\"nix_darwin\":\"\",\"mlx\":\"0.26\",\"mlx_lm\":\"0.29\",\"macos\":\"\",\"model\":\"org/default\",\"model_revision\":\"\"}"
make_cached_model org/default "$model_revision_default"
make_cached_model user/override bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
make_cached_model user/huge cccccccccccccccccccccccccccccccccccccccc
export CLUSTER_SW_VERS_BIN="$tmp/bin/sw-vers"
export CLUSTER_STAT_BIN="$tmp/bin/stat"
export CLUSTER_DARWIN_VERSION_BIN="$tmp/bin/darwin-version"
export CLUSTER_STATIC_PEER_IP=peer
export CLUSTER_STATIC_SELF_IP=self
export CLUSTER_PEER_STATE_PORT=11442
export CLUSTER_PEER_STATE_TIMEOUT_SECS=2
export CLUSTER_JOIN_TIMEOUT_SECS=100
export CLUSTER_HTTP_PORT=8000
export EVENTS="$tmp/events"
export CLUSTER_SSH_BIN="$tmp/bin/ssh"
export CLUSTER_MODEL_STAT_BIN="$tmp/bin/model-stat"
export FAKE_SSH_LOG="$tmp/ssh.log"
export FAKE_LAUNCHCTL_LOG="$tmp/launchctl.log"
: > "$FAKE_LAUNCHCTL_LOG"
export CLUSTER_LAUNCHCTL_BIN="$tmp/bin/launchctl"
export FAKE_MTIME=99
export CLUSTER_RANK_LABEL=dev.test.rank
export CLUSTER_LIFECYCLE_LOG="$tmp/lifecycle.log"
FAKE_NOW=1000
check 'boot epoch fixture' 100 "$(current_boot_epoch)"
echo 'the responder resets stale or missing state and keeps current-boot state:'
export CLUSTER_STAT_BIN="$tmp/bin/stat"
export CLUSTER_STATE_FILE="$tmp/state/link-state"
export CLUSTER_PEER_STATE_FILE="$tmp/state/peer-state.json"
printf 'up\n' > "$CLUSTER_STATE_FILE"
printf '{"armed":true}\n' > "$CLUSTER_PEER_STATE_FILE"
FAKE_MTIME=99
if peer_state_reset_if_needed > "$tmp/reset-old.log"; then
  check 'old peer state disarmed' false "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  check 'old peer state link down' down "$(cat "$CLUSTER_STATE_FILE")"
  contains 'old peer state reset logged' 'reason=peer-state-from-previous-boot' "$(cat "$tmp/reset-old.log")"
else
  echo '  FAIL old peer state reset failed'
  fail=1
fi
printf 'up\n' > "$CLUSTER_STATE_FILE"
printf '{"armed":true}\n' > "$CLUSTER_PEER_STATE_FILE"
FAKE_MTIME=100
if peer_state_reset_if_needed > "$tmp/reset-current.log"; then
  check 'current-boot peer state retained' true "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  check 'current-boot link state retained' up "$(cat "$CLUSTER_STATE_FILE")"
  check 'current-boot reset is silent' 0 "$(wc -c < "$tmp/reset-current.log" | tr -d ' ')"
else
  echo '  FAIL current-boot state was reset'
  fail=1
fi
current_boot_epoch() { :; }
if peer_state_reset_if_needed > "$tmp/reset-unknown-boot.log"; then
  check 'unreadable boot time disarms peer state' false "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  check 'unreadable boot time takes link down' down "$(cat "$CLUSTER_STATE_FILE")"
  contains 'unreadable boot time reset logged' 'reason=boot-time-unreadable' "$(cat "$tmp/reset-unknown-boot.log")"
else
  echo '  FAIL unreadable boot time did not fail closed'
  fail=1
fi
rm -f "$CLUSTER_PEER_STATE_FILE"
printf 'up\n' > "$CLUSTER_STATE_FILE"
if peer_state_reset_if_needed > "$tmp/reset-missing.log"; then
  check 'missing peer state recreated disarmed' false "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  contains 'missing peer state reset logged' 'reason=peer-state-missing' "$(cat "$tmp/reset-missing.log")"
else
  echo '  FAIL missing peer state reset failed'
  fail=1
fi

FAKE_NOW=1000
echo 'peer state writer includes the current software contract:'
if peer_state_write true 1000; then
  check 'writer armed' true "$(jq -r '.armed' "$CLUSTER_PEER_STATE_FILE")"
  check 'writer armed_at' 1000 "$(jq -r '.armed_at' "$CLUSTER_PEER_STATE_FILE")"
  check 'writer macOS build' build-a "$(jq -r '.software.macos' "$CLUSTER_PEER_STATE_FILE")"
  check 'writer mlx_lm key' 0.29 "$(jq -r '.software.mlx_lm' "$CLUSTER_PEER_STATE_FILE")"
  check 'writer model key' org/default "$(jq -r '.software.model' "$CLUSTER_PEER_STATE_FILE")"
  check 'writer model revision key' '' "$(jq -r '.software.model_revision' "$CLUSTER_PEER_STATE_FILE")"
else
  echo '  FAIL peer_state_write refused valid software data'
  fail=1
fi
JOIN_MODEL_ID=user/override
JOIN_MODEL_REVISION=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
if peer_state_write true 1000; then
  check 'writer publishes selected model id' user/override "$(jq -r '.software.model' "$CLUSTER_PEER_STATE_FILE")"
  check 'writer publishes selected model revision' "$JOIN_MODEL_REVISION" "$(jq -r '.software.model_revision' "$CLUSTER_PEER_STATE_FILE")"
else
  echo '  FAIL peer_state_write refused selected model data'
  fail=1
fi
unset JOIN_MODEL_ID JOIN_MODEL_REVISION

peer_state_software_json() {
  jq -cn --arg model "${JOIN_MODEL_ID:-org/default}" \
    --arg model_revision "${JOIN_MODEL_REVISION:-$model_revision_default}" \
    '{nix_ai:"rev-a",nix_darwin:"",mlx:"0.26",mlx_lm:"0.29",macos:"build-a",model:$model,model_revision:$model_revision}'
}
PEER_JSON=''
peer_state_fetch() { PEER_STATE_RAW="$PEER_JSON"; }
make_peer_json() {
  local armed_at="$1" software="$2"
  PEER_JSON="$(jq -nc --argjson armed_at "$armed_at" --argjson software "$software" \
    '{armed:true,armed_at:$armed_at,generation:"gen-a",software:$software}')"
}

echo 'peer poll requires a fresh arm and exact version match:'
local_software="$(peer_state_software_json)"
make_peer_json 995 "$local_software"
peer_state_fetch
check 'fake peer fetch returns the fixture' "$PEER_JSON" "$PEER_STATE_RAW"
if peer_armed_read; then
  check 'matched peer armed_at' 995 "$PEER_ARMED_AT"
else
  echo "  FAIL matching peer refused: $PEER_GATE_REASON"
  fail=1
fi

FAKE_NOW=1000
make_peer_json 899 "$local_software"
if peer_armed_read; then
  echo '  FAIL stale peer arm passed'
  fail=1
else
  contains 'stale arm refusal' 'peer-arm-stale' "$PEER_GATE_REASON"
fi

mismatched_software='{"nix_ai":"rev-b","nix_darwin":"","mlx":"0.26","mlx_lm":"0.29","macos":"build-a","model":"org/default","model_revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
make_peer_json 995 "$mismatched_software"
if cluster_join_peer_poll > "$tmp/mismatch.log" 2>&1; then
  echo '  FAIL generation mismatch poll passed'
  fail=1
else
  mismatch_rc=$?
  check 'generation mismatch poll is a hard refusal' 2 "$mismatch_rc"
  contains 'generation mismatch reason names the differing key' 'generation-mismatch key=nix_ai local=rev-a peer=rev-b' "$PEER_GATE_REASON"
  contains 'generation mismatch is logged as REFUSE' 'cluster-join: peer-state REFUSE reason=generation-mismatch' "$(cat "$tmp/mismatch.log")"
fi

JOIN_MODEL_ID=org/default
JOIN_MODEL_REVISION="$model_revision_default"
export JOIN_MODEL_ID JOIN_MODEL_REVISION
local_software="$(peer_state_software_json)"
mismatched_software="$(jq -cn --argjson software "$local_software" \
  '$software | .model_revision = "dddddddddddddddddddddddddddddddddddddddd"')"
make_peer_json 995 "$mismatched_software"
if cluster_join_peer_poll > "$tmp/model-mismatch.log" 2>&1; then
  echo '  FAIL model revision mismatch poll passed'
  fail=1
else
  mismatch_rc=$?
  check 'model revision mismatch is a hard refusal' 2 "$mismatch_rc"
  contains 'model revision mismatch names the key' \
    "generation-mismatch key=model_revision local=$model_revision_default peer=dddddddddddddddddddddddddddddddddddddddd" "$PEER_GATE_REASON"
fi

echo 'aligned starts use the same boundary in either arm order:'
check 'coordinator arms first' 220 "$(cluster_start_at 100 200)"
check 'worker arms first' 220 "$(cluster_start_at 200 100)"

echo 'a disarm or missed window never kickstarts a rank:'
peer_armed_read() { PEER_GATE_REASON='peer-not-armed'; return 1; }
pd_start_gate() { return 0; }
if peer_armed_read; then
  echo '  FAIL disarm fixture unexpectedly passed'
  fail=1
else
  contains 'disarm fixture reason' peer-not-armed "$PEER_GATE_REASON"
fi
check 'PD gate fixture is healthy' 0 "$(pd_start_gate && echo 0 || echo 1)"
if cluster_final_rank_start 100 995 > "$tmp/disarm.log" 2>&1; then
  echo '  FAIL disarmed peer reached kickstart'
  fail=1
else
  contains 'disarm is logged' 'REFUSE reason=peer-not-armed' "$(cat "$tmp/disarm.log")"
fi
check 'disarm issued no kickstart' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"

peer_armed_read() { PEER_ARMED_AT=995; return 0; }
FAKE_NOW=101
if cluster_final_rank_start 100 995 > "$tmp/window.log" 2>&1; then
  echo '  FAIL missed window reached kickstart'
  fail=1
else
  contains 'missed window is refused' 'REFUSE reason=missed-start-window' "$(cat "$tmp/window.log")"
fi
check 'missed window issued no kickstart' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"

setup_local_pass() {
  rm -f "$CLUSTER_STATE_DIR/rank-model"
  pd_start_gate() { printf 'J1\n' >> "$EVENTS"; return 0; }
  link_prep_ok() { printf 'J2\n' >> "$EVENTS"; return 0; }
  set_wired_limit() { printf 'J3\n' >> "$EVENTS"; return 0; }
  cluster_join_quiesce() { quiesced=true; printf 'J4\n' >> "$EVENTS"; }
  rank_start_room_ok() { printf 'J5 shard=%s\n' "${CLUSTER_SHARD_MEMORY_MB:-unset}" >> "$EVENTS"; return 0; }
  peer_state_write() { printf 'arm\n' >> "$EVENTS"; return "${FAKE_ARM_RC:-0}"; }
  link_state_write() { printf 'link-%s\n' "$1" >> "$EVENTS"; return 0; }
  cluster_join_peer_poll() { JOIN_PEER_ARMED_AT=1000; return 0; }
  cluster_final_rank_start() { cluster_rank_model_write || return 1; printf 'J9\n' >> "$EVENTS"; return 0; }
  cluster_sleep_until() { return 0; }
  cluster_teardown() { printf 'teardown\n' >> "$EVENTS"; TEARDOWN_REBOOT=0; return "${FAKE_TEARDOWN_RC:-0}"; }
  curl() { return 0; }
  rank_process_running() { return 0; }
  rank_process_pids() { printf '123\n'; }
  pd_held_count() { PD_HELD=0; return 0; }
  cluster_lifecycle_log_start() { exec > "$CLUSTER_LIFECYCLE_LOG" 2>&1; }
  FAKE_NOW=1000
}

echo 'the coordinator completes J1-J5 before starting its worker, then arms at J6:'
CLUSTER_ROLE=coordinator
CLUSTER_PEER_SSH=user@peer
CLUSTER_JOIN_TIMEOUT_SECS=10
CLUSTER_SHARDING_MODE=pipeline
FAKE_SSH_RC=0
unset FAKE_SSH_SLEEP FAKE_SSH_PID_FILE
export CLUSTER_ROLE CLUSTER_PEER_SSH CLUSTER_JOIN_TIMEOUT_SECS CLUSTER_SHARDING_MODE FAKE_SSH_RC
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
: > "$EVENTS"
setup_local_pass
if (cluster_join_main) > /dev/null 2>&1; then
  check 'local and worker join both pass' 0 "$?"
else
  echo '  FAIL coordinator join failed when both sides passed'; fail=1
fi
check 'worker join called ssh once' 1 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"
check 'worker join arguments' '-o BatchMode=yes -o ConnectTimeout=10 user@peer cluster-join --worker' "$(cat "$FAKE_SSH_LOG")"
contains 'default model keeps configured shard memory' 'J5 shard=128' "$(cat "$EVENTS")"
check 'default model keeps configured model id' org/default "$(sed -n '1p' "$CLUSTER_STATE_DIR/rank-model")"
check 'default model keeps configured sharding mode' pipeline "$(sed -n '2p' "$CLUSTER_STATE_DIR/rank-model")"
j5_line="$(grep -n 'cluster-join: room PASS' "$CLUSTER_LIFECYCLE_LOG" | cut -d: -f1)"
start_line="$(grep -n 'cluster-join: peer-ssh started pid=' "$CLUSTER_LIFECYCLE_LOG" | cut -d: -f1)"
j6_line="$(grep -n 'cluster-join: J6 arm' "$CLUSTER_LIFECYCLE_LOG" | cut -d: -f1)"
check 'worker ssh starts between J5 and J6' yes "$([ "$j5_line" -lt "$start_line" ] && [ "$start_line" -lt "$j6_line" ] && echo yes || echo no)"
contains 'worker stdout is prefixed' 'worker: remote stdout' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
contains 'worker stderr is prefixed' 'worker: remote stderr' "$(cat "$CLUSTER_LIFECYCLE_LOG")"

echo 'a coordinator J1 refusal does not contact the worker:'
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
pd_start_gate() { return 1; }
if (cluster_join_main) > /dev/null 2>&1; then
  echo '  FAIL coordinator J1 refusal returned success'; fail=1
else
  check 'J1 refusal exits 1' 1 "$?"
fi
check 'J1 refusal did not call ssh' 0 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"
contains 'J1 refusal is logged before any worker start' 'cluster-join: J1 pd-start-gate' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
if grep -q 'peer-ssh started\|J5 room PASS\|J6 arm' "$CLUSTER_LIFECYCLE_LOG"; then
  echo '  FAIL a J1 refusal passed its pre-spend gate'; fail=1
else
  echo '  ok   J1 refusal stops before J5 and ssh'
fi

echo 'a worker invocation never starts another ssh:'
CLUSTER_ROLE=worker
CLUSTER_WORKER_STABLE_SECS=0
export CLUSTER_ROLE CLUSTER_WORKER_STABLE_SECS
: > "$FAKE_SSH_LOG"
setup_local_pass
if (cluster_join_main --worker --model user/override --pipeline) > /dev/null 2>&1; then
  check 'worker join accepts its invocation and passes' 0 "$?"
else
  echo '  FAIL worker join failed'; fail=1
fi
contains 'worker invocation intent is logged' 'peer worker invocation accepted' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
contains 'worker parses model and pipeline flags' \
  'cluster-join: model id=user/override rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb total_mb=1 shard_mb=1 sharding=pipeline' \
  "$(cat "$CLUSTER_LIFECYCLE_LOG")"
check 'worker with peerSsh configured never calls ssh' 0 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"

echo 'a failed worker join after local formation tears down the coordinator:'
CLUSTER_ROLE=coordinator
FAKE_SSH_RC=42
export CLUSTER_ROLE FAKE_SSH_RC
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
: > "$EVENTS"
setup_local_pass
if (cluster_join_main) > /dev/null 2>&1; then
  echo '  FAIL coordinator accepted a failed worker join'; fail=1
else
  check 'failed worker join exits nonzero' 1 "$?"
fi
check 'failed worker ssh called once' 1 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"
contains 'worker failure rc is logged' 'cluster-join: REFUSE reason=peer-join-failed rc=42' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
contains 'local join formed before remote failure handling' 'decision=formed' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
check 'worker failure runs coordinator teardown' yes "$(grep -qx teardown "$EVENTS" && echo yes || echo no)"

echo 'a worker reboot-required result propagates as 3; other ssh errors stay 1:'
for pair in '255 1' '3 3'; do
  read -r FAKE_SSH_RC expected_rc <<< "$pair"
  export FAKE_SSH_RC
  : > "$FAKE_SSH_LOG"
  : > "$CLUSTER_LIFECYCLE_LOG"
  : > "$EVENTS"
  setup_local_pass
  if (cluster_join_main) > /dev/null 2>&1; then
    join_rc=0
  else
    join_rc=$?
  fi
  check "worker join rc=$FAKE_SSH_RC maps to coordinator rc=$expected_rc" "$expected_rc" "$join_rc"
  contains 'worker failure rc is logged' \
    "cluster-join: REFUSE reason=peer-join-failed rc=$FAKE_SSH_RC" "$(cat "$CLUSTER_LIFECYCLE_LOG")"
  check 'failed worker join tears down the coordinator' yes "$(grep -qx teardown "$EVENTS" && echo yes || echo no)"
done

echo 'a worker ssh exceeding the bound is terminated and reaped on local exit:'
CLUSTER_JOIN_TIMEOUT_SECS=0
FAKE_SSH_RC=0
FAKE_SSH_SLEEP=60
FAKE_SSH_PID_FILE="$tmp/ssh.pid"
export CLUSTER_JOIN_TIMEOUT_SECS FAKE_SSH_RC FAKE_SSH_SLEEP FAKE_SSH_PID_FILE
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
: > "$EVENTS"
setup_local_pass
peer_state_write() { return 1; }
sleep() { SECONDS=$((SECONDS + 31)); }
if (cluster_join_main) > /dev/null 2>&1; then
  echo '  FAIL local J6 failure returned success'; fail=1
else
  check 'local J6 failure keeps its exit code' 1 "$?"
fi
contains 'peer ssh timeout is logged' 'cluster-join: peer-ssh timeout' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
contains 'timeout sends TERM to the worker ssh' 'cluster-join: peer-ssh exit rc=143' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
if [ -s "$FAKE_SSH_PID_FILE" ] && kill -0 "$(cat "$FAKE_SSH_PID_FILE")" 2> /dev/null; then
  echo '  FAIL timed-out worker ssh remains alive'; fail=1
else
  echo '  ok   timed-out worker ssh was reaped'
fi

echo 'a TERM exit trap also reaps a started worker ssh:'
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
if (
  CLUSTER_ROLE=coordinator
  CLUSTER_PEER_SSH=user@peer
  CLUSTER_JOIN_TIMEOUT_SECS=0
  FAKE_SSH_SLEEP=60
  formed=true
  quiesced=false
  JOIN_EXIT_ACTIVE=false
  JOIN_SIGNAL_RC=0
  CLUSTER_PEER_SSH_PID=
  CLUSTER_PEER_SSH_RC=0
  cluster_lifecycle_log_start
  trap cluster_join_exit EXIT
  trap 'cluster_join_signal 143' TERM
  cluster_peer_ssh_start
  while [ ! -s "$FAKE_SSH_PID_FILE" ]; do /bin/sleep 0.01; done
  kill -TERM "$BASHPID"
) > /dev/null 2>&1; then
  echo '  FAIL TERM test command returned success'; fail=1
else
  check 'TERM handler preserves its exit code' 143 "$?"
fi
contains 'TERM exit reaped the peer ssh' 'cluster-join: peer-ssh exit rc=143' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
if kill -0 "$(cat "$FAKE_SSH_PID_FILE")" 2> /dev/null; then
  echo '  FAIL worker ssh remains alive after TERM'; fail=1
else
  echo '  ok   worker ssh was reaped by the TERM exit trap'
fi

setup_local_pass
cluster_teardown
check 'teardown fixture is directly callable' yes "$(grep -qx teardown "$EVENTS" && echo yes || echo no)"
: > "$EVENTS"

echo 'model validation and fit refuse before J1 and before worker ssh:'
CLUSTER_ROLE=coordinator
CLUSTER_PEER_SSH=user@peer
export CLUSTER_ROLE CLUSTER_PEER_SSH
setup_local_pass
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
if (cluster_join_main --model user/missing) > /dev/null 2>&1; then
  echo '  FAIL missing model cache passed'
  fail=1
else
  check 'missing model cache exits 1' 1 "$?"
fi
contains 'missing cache refusal includes refs path' \
  "$HF_HOME/hub/models--user--missing/refs/main" "$(cat "$CLUSTER_LIFECYCLE_LOG")"
if grep -q 'J1 pd-start-gate' "$CLUSTER_LIFECYCLE_LOG"; then
  echo '  FAIL missing cache reached J1'; fail=1
else
  echo '  ok   missing cache refuses before J1'
fi
check 'missing cache does not start worker ssh' 0 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"

setup_local_pass
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
if (cluster_join_main --model 'user/bad?model') > /dev/null 2>&1; then
  echo '  FAIL invalid model id passed'
  fail=1
else
  check 'invalid model id exits 1' 1 "$?"
fi
contains 'invalid model id is refused' 'REFUSE reason=model-not-cached detail=invalid-model-id' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
if grep -q 'J1 pd-start-gate' "$CLUSTER_LIFECYCLE_LOG"; then
  echo '  FAIL invalid model id reached J1'; fail=1
else
  echo '  ok   invalid model id refuses before J1'
fi
check 'invalid model id does not start worker ssh' 0 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"

setup_local_pass
CLUSTER_JOIN_TIMEOUT_SECS=10
unset FAKE_SSH_SLEEP FAKE_SSH_PID_FILE
FAKE_SSH_RC=0
export CLUSTER_JOIN_TIMEOUT_SECS FAKE_SSH_RC
export FAKE_MODEL_SIZE=104857600 CLUSTER_WIRED_LIMIT_MB=50 CLUSTER_COMPOSITOR_RESERVE_MB=20
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
if (cluster_join_main --model user/huge) > /dev/null 2>&1; then
  echo '  FAIL oversized model passed'
  fail=1
else
  check 'oversized model exits 1' 1 "$?"
fi
contains 'oversized model refusal is logged' 'REFUSE reason=model-too-large shard_mb=55 ceiling_mb=30' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
if grep -q 'J1 pd-start-gate' "$CLUSTER_LIFECYCLE_LOG"; then
  echo '  FAIL oversized model reached J1'; fail=1
else
  echo '  ok   oversized model refuses before J1'
fi
check 'oversized model does not start worker ssh' 0 "$(wc -l < "$FAKE_SSH_LOG" | tr -d ' ')"

echo 'a cached model override is logged, persisted, and forwarded to the worker:'
export FAKE_MODEL_SIZE=20971520 CLUSTER_WIRED_LIMIT_MB=2000 CLUSTER_COMPOSITOR_RESERVE_MB=100
setup_local_pass
CLUSTER_JOIN_TIMEOUT_SECS=10
unset FAKE_SSH_SLEEP FAKE_SSH_PID_FILE
FAKE_SSH_RC=0
export CLUSTER_JOIN_TIMEOUT_SECS FAKE_SSH_RC
: > "$FAKE_SSH_LOG"
: > "$CLUSTER_LIFECYCLE_LOG"
if (cluster_join_main --model user/override --pipeline) > /dev/null 2>&1; then
  check 'cached model override join passes' 0 "$?"
else
  echo '  FAIL cached model override join failed'; fail=1
fi
contains 'model fit and selection are logged' \
  'cluster-join: model id=user/override rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb total_mb=20 shard_mb=11 sharding=pipeline' \
  "$(cat "$CLUSTER_LIFECYCLE_LOG")"
contains 'J5 receives computed shard memory' 'J5 shard=11' "$(cat "$EVENTS")"
check 'rank-model first line is the selected id' user/override "$(sed -n '1p' "$CLUSTER_STATE_DIR/rank-model")"
check 'rank-model second line is the selected mode' pipeline "$(sed -n '2p' "$CLUSTER_STATE_DIR/rank-model")"
check 'worker ssh receives model and pipeline flags' \
  '-o BatchMode=yes -o ConnectTimeout=10 user@peer cluster-join --worker --model user/override --pipeline' \
  "$(cat "$FAKE_SSH_LOG")"

echo 'rank launcher applies the saved model and sharding mode:'
rank_args_out="$(CLUSTER_IBV_MATRIX_FILE="$tmp/state/ibv-matrix.json" \
  CLUSTER_RDMA_DEVICE=rdma_test bash "${RANK_LAUNCH:?set RANK_LAUNCH to cluster-rank-launch.sh}" \
  /bin/echo --model org/default 2> "$tmp/rank-launch.log")"
check 'pipeline state replaces model and adds flag' '--model user/override --pipeline' "$rank_args_out"
contains 'rank model override log is exact' 'cluster-rank: model override id=user/override sharding=pipeline' "$(cat "$tmp/rank-launch.log")"
rm -f "$CLUSTER_STATE_DIR/rank-model"
rank_args_out="$(CLUSTER_IBV_MATRIX_FILE="$tmp/state/ibv-matrix.json" \
  CLUSTER_RDMA_DEVICE=rdma_test bash "$RANK_LAUNCH" /bin/echo --model org/default --pipeline)"
check 'missing state leaves argv unchanged' '--model org/default --pipeline' "$rank_args_out"
printf 'user/tensor\ntensor\n' > "$CLUSTER_STATE_DIR/rank-model"
rank_args_out="$(CLUSTER_IBV_MATRIX_FILE="$tmp/state/ibv-matrix.json" \
  CLUSTER_RDMA_DEVICE=rdma_test bash "$RANK_LAUNCH" /bin/echo --model org/default --pipeline)"
check 'tensor state replaces model and removes flag' '--model user/tensor' "$rank_args_out"

echo 'teardown deletes the saved rank model:'
source modules/mlx/scripts/cluster-teardown.sh
peer_state_write() { return 0; }
rank_process_absent() { return 0; }
pd_held_count() { PD_HELD=0; return 0; }
set_wired_limit() { return 0; }
restore_normal_serving() { return 0; }
link_state_write() { return 0; }
printf 'user/tensor\ntensor\n' > "$CLUSTER_STATE_DIR/rank-model"
if cluster_teardown > "$tmp/teardown-model.log" 2>&1; then
  if [ ! -e "$CLUSTER_STATE_DIR/rank-model" ]; then
    echo '  ok   teardown removes rank-model'
  else
    echo '  FAIL teardown left rank-model'; fail=1
  fi
else
  echo '  FAIL teardown failed before removing rank-model'; fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo 'join handshake checks FAILED' >&2
  exit 1
fi
echo 'join handshake checks passed'
