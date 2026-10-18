#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"

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
chmod +x "$tmp/bin/sw-vers" "$tmp/bin/ssh" "$tmp/bin/launchctl" "$tmp/bin/stat"

source modules/mlx/scripts/cluster-boot-scope.sh
source modules/mlx/scripts/cluster-peer-state-write.sh
source modules/mlx/scripts/cluster-peer-state.sh
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
  else
    command date "$@"
  fi
}
current_boot_epoch() { printf '100\n'; }
generation_local_rev() { printf 'gen-a\n'; }
export CLUSTER_PEER_STATE_FILE="$tmp/state/peer-state.json"
export CLUSTER_STATE_FILE="$tmp/state/link-state"
export CLUSTER_SOFTWARE_JSON='{"nix_ai":"rev-a","nix_darwin":"","mlx":"0.26","mlx_lm":"0.29","macos":""}'
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
else
  echo '  FAIL peer_state_write refused valid software data'
  fail=1
fi

peer_state_software_json() {
  printf '%s\n' '{"nix_ai":"rev-a","nix_darwin":"","mlx":"0.26","mlx_lm":"0.29","macos":"build-a"}'
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

mismatched_software='{"nix_ai":"rev-b","nix_darwin":"","mlx":"0.26","mlx_lm":"0.29","macos":"build-a"}'
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
  contains 'disarm is logged' 'peer-state REFUSE reason=peer-not-armed' "$(cat "$tmp/disarm.log")"
fi
check 'disarm issued no kickstart' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"

peer_armed_read() { PEER_ARMED_AT=995; return 0; }
FAKE_NOW=101
if cluster_final_rank_start 100 995 > "$tmp/window.log" 2>&1; then
  echo '  FAIL missed window reached kickstart'
  fail=1
else
  contains 'missed window is refused' 'REFUSE missed start window' "$(cat "$tmp/window.log")"
fi
check 'missed window issued no kickstart' 0 "$(grep -c 'kickstart' "$FAKE_LAUNCHCTL_LOG" || true)"

setup_local_pass() {
  pd_start_gate() { printf 'J1\n' >> "$EVENTS"; return 0; }
  link_prep_ok() { printf 'J2\n' >> "$EVENTS"; return 0; }
  set_wired_limit() { printf 'J3\n' >> "$EVENTS"; return 0; }
  cluster_join_quiesce() { quiesced=true; printf 'J4\n' >> "$EVENTS"; }
  rank_start_room_ok() { printf 'J5\n' >> "$EVENTS"; return 0; }
  peer_state_write() { printf 'arm\n' >> "$EVENTS"; return "${FAKE_ARM_RC:-0}"; }
  link_state_write() { printf 'link-%s\n' "$1" >> "$EVENTS"; return 0; }
  cluster_join_peer_poll() { JOIN_PEER_ARMED_AT=1000; return 0; }
  cluster_final_rank_start() { printf 'J9\n' >> "$EVENTS"; return 0; }
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
FAKE_SSH_RC=0
unset FAKE_SSH_SLEEP FAKE_SSH_PID_FILE
export CLUSTER_ROLE CLUSTER_PEER_SSH CLUSTER_JOIN_TIMEOUT_SECS FAKE_SSH_RC
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
if (cluster_join_main --worker) > /dev/null 2>&1; then
  check 'worker join accepts its invocation and passes' 0 "$?"
else
  echo '  FAIL worker join failed'; fail=1
fi
contains 'worker invocation intent is logged' 'peer worker invocation accepted' "$(cat "$CLUSTER_LIFECYCLE_LOG")"
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

if [ "$fail" -ne 0 ]; then
  echo 'join handshake checks FAILED' >&2
  exit 1
fi
echo 'join handshake checks passed'
