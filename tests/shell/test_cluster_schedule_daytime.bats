#!/usr/bin/env bats
# Daytime agent: modules/mlx/scripts/cluster-schedule-daytime.sh.
#
# Stubs follow test_cluster_schedule_preflight.bats: fake binaries behind the
# CLUSTER_*_BIN seams, steered by FAKE_* variables. The detach command is a stub
# that records its arguments, so each case sees exactly which lifecycle call the
# daytime run made. Every case also checks that no path started a rank, ran a
# join or link prep, or changed the wired ceiling.
#
# Needs bats and jq on PATH.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$STUBS" "$BATS_TEST_TMPDIR/state" "$BATS_TEST_TMPDIR/LaunchAgents"
  : > "$CALLS"

  write_stub pgrep <<'STUB'
if [ "${FAKE_PGREP_RC:-1}" -eq 0 ]; then
  printf '%s\n' 4242
fi
exit "${FAKE_PGREP_RC:-1}"
STUB
  write_stub curl <<'STUB'
[ "${FAKE_CURL_RC:-0}" -eq 0 ] || exit "$FAKE_CURL_RC"
printf '%s' "$FAKE_PEER_JSON"
STUB
  write_stub launchctl <<'STUB'
printf 'launchctl %s\n' "$*" >> "$CALLS_LOG"
exit 0
STUB
  write_stub detach <<'STUB'
printf 'detach %s\n' "$*" >> "$CALLS_LOG"
exit "${FAKE_DETACH_RC:-0}"
STUB
  # Tripwires: the daytime run must never reach these.
  write_stub join <<'STUB'
printf 'join %s\n' "$*" >> "$CALLS_LOG"
STUB
  write_stub sysctl <<'STUB'
printf 'sysctl %s\n' "$*" >> "$CALLS_LOG"
STUB

  export CALLS_LOG="$CALLS"
  export CLUSTER_ROLE=coordinator
  export CLUSTER_RANK_LABEL=dev.test.rank
  export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'
  export CLUSTER_PGREP_BIN="$STUBS/pgrep"
  export CLUSTER_CURL_BIN="$STUBS/curl"
  export CLUSTER_LAUNCHCTL_BIN="$STUBS/launchctl"
  export CLUSTER_SYSCTL_BIN="$STUBS/sysctl"
  export CLUSTER_DETACH_BIN="$STUBS/detach"
  export CLUSTER_JOIN_BIN="$STUBS/join"
  export CLUSTER_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CLUSTER_STATE_FILE="$CLUSTER_STATE_DIR/link-state"
  export CLUSTER_PEER_STATE_FILE="$CLUSTER_STATE_DIR/peer-state.json"
  export CLUSTER_LAUNCH_AGENTS_DIR="$BATS_TEST_TMPDIR/LaunchAgents"
  export CLUSTER_SERVER_LABELS=dev.test.server
  export CLUSTER_STATIC_PEER_IP=192.0.2.2
  export CLUSTER_PEER_STATE_PORT=18080
  export CLUSTER_PEER_STATE_TIMEOUT_SECS=2
  export CLUSTER_INVOKER=dev.mlx-cluster.schedule-daytime

  export FAKE_PGREP_RC=1
  export FAKE_CURL_RC=0
  export FAKE_DETACH_RC=0
  export SESSION=20261110T230000Z-0123abcd
  export FAKE_PEER_JSON='{"armed":false,"phase":"abort","session":""}'

  touch "$CLUSTER_LAUNCH_AGENTS_DIR/dev.test.server.plist"
  printf 'down\n' > "$CLUSTER_STATE_FILE"
  printf '{"armed":false}\n' > "$CLUSTER_PEER_STATE_FILE"
  PENDING="$CLUSTER_STATE_DIR/restore-pending"

  local layer
  for layer in cluster-rank-status cluster-peer-state cluster-schedule-common cluster-schedule-daytime; do
    # shellcheck source=/dev/null
    source "$REPO/modules/mlx/scripts/$layer.sh"
  done
}

write_stub() {
  {
    printf '#!%s\n' "$BASH"
    cat
  } > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

calls() {
  grep -c "$1" "$CALLS" || true
}

# No rank kickstart or bootstrap, no join, no link prep, no wired ceiling change.
assert_no_rank_start() {
  [ "$(calls 'kickstart')" = 0 ]
  [ "$(calls 'bootstrap')" = 0 ]
  [ "$(calls "$CLUSTER_RANK_LABEL")" = 0 ]
  [ "$(calls '^join')" = 0 ]
  [ "$(calls 'link-prep')" = 0 ]
  [ "$(calls '^sysctl')" = 0 ]
}

peer_armed() {
  export FAKE_PEER_JSON="{\"armed\":true,\"phase\":\"formed\",\"session\":\"$SESSION\"}"
}

@test 'a restore-pending marker with the rank still live holds without a detach' {
  printf 'session=%s\n' "$SESSION" > "$PENDING"
  FAKE_PGREP_RC=0 run schedule_daytime_main
  [ "$status" -eq 0 ]
  [[ "$output" == *'guard=D0 decision=hold reason=rank-survivor-pending'* ]]
  [ "$(calls '^detach')" = 0 ]
  assert_no_rank_start
}

@test 'a restore-pending marker with the rank gone finishes the restore through detach' {
  printf 'session=%s\n' "$SESSION" > "$PENDING"
  run schedule_daytime_main
  [ "$status" -eq 0 ]
  [[ "$output" == *'guard=D0 decision=pass reason=finish-restore'* ]]
  [[ "$output" != *'guard=D1'* ]]
  [ "$(calls '^detach $')" = 1 ]
  assert_no_rank_start
}

@test 'a restore-pending marker with an unanswerable rank probe holds' {
  printf 'session=%s\n' "$SESSION" > "$PENDING"
  FAKE_PGREP_RC=2 run schedule_daytime_main
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=D0 decision=hold reason=rank-probe-unanswerable'* ]]
  [ "$(calls '^detach')" = 0 ]
  assert_no_rank_start
}

@test 'a clustered host still runs the existing detach' {
  FAKE_PGREP_RC=0 run schedule_daytime_main
  [ "$status" -eq 0 ]
  [[ "$output" == *'guard=D1 decision=pass reason=clustered'* ]]
  [ "$(calls '^detach $')" = 1 ]
  assert_no_rank_start
}
