#!/usr/bin/env bats
# Read-only nightly preflight: modules/mlx/scripts/cluster-schedule-preflight.sh.
#
# Stubs follow tests/test-pd-gate.sh: fake binaries behind the CLUSTER_*_BIN seams,
# steered by FAKE_* variables. The layers are sourced, so each case calls
# schedule_preflight_main directly. Every case also checks that the preflight
# reached none of the quiesce, arm, kickstart or link-state-write paths.
#
# Needs bats and jq on PATH.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  MARKER="$BATS_TEST_TMPDIR/marker"
  mkdir -p "$STUBS"
  : > "$CALLS"

  write_stub pgrep <<'STUB'
if [ "${FAKE_PGREP_RC:-1}" -eq 0 ]; then
  printf '%s\n' "${FAKE_PGREP_PID:-4242}"
fi
exit "${FAKE_PGREP_RC:-1}"
STUB
  write_stub ioclasscount <<'STUB'
case "$1" in
  *ProtectionDomain)
    printf '%s = %s\n' "$1" "${FAKE_PD_HELD:-0}"
    ;;
  *)
    printf '%s = 0\n' "$1"
    ;;
esac
exit 0
STUB
  write_stub ibv_devinfo <<'STUB'
printf 'hca_id: rdma_test\nmax_pd: 11\n'
STUB
  write_stub sysctl <<'STUB'
printf 'vm.swapusage: total = 2048.00M  used = %s.00M  free = 1024.00M  (encrypted)\n' "${FAKE_SWAP_USED_MB:-100}"
STUB
  write_stub curl <<'STUB'
[ "${FAKE_CURL_RC:-0}" -eq 0 ] || exit "$FAKE_CURL_RC"
printf '%s' "$FAKE_PEER_JSON"
STUB
  write_stub darwin-version <<'STUB'
printf '{"configurationRevision": "%s"}\n' "${FAKE_LOCAL_REV:-rev-a}"
STUB
  write_stub sw-vers <<'STUB'
printf '%s\n' "${FAKE_MACOS:-25F71}"
STUB
  # Records every launchctl call. The preflight must make none.
  write_stub launchctl <<'STUB'
printf 'launchctl %s\n' "$*" >> "$CALLS_LOG"
exit 0
STUB

  export CALLS_LOG="$CALLS"
  export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'
  export CLUSTER_RDMA_DEVICE=rdma_test
  export CLUSTER_PD_DEVICE_BUDGET=11
  export CLUSTER_PD_RESERVE=5
  export CLUSTER_PGREP_BIN="$STUBS/pgrep"
  export CLUSTER_IOCLASSCOUNT_BIN="$STUBS/ioclasscount"
  export CLUSTER_IBV_DEVINFO_BIN="$STUBS/ibv_devinfo"
  export CLUSTER_SYSCTL_BIN="$STUBS/sysctl"
  export CLUSTER_CURL_BIN="$STUBS/curl"
  export CLUSTER_DARWIN_VERSION_BIN="$STUBS/darwin-version"
  export CLUSTER_SW_VERS_BIN="$STUBS/sw-vers"
  export CLUSTER_LAUNCHCTL_BIN="$STUBS/launchctl"
  export CLUSTER_STATE_FILE="$BATS_TEST_TMPDIR/link-state"
  export CLUSTER_PEER_STATE_FILE="$BATS_TEST_TMPDIR/peer-state.json"
  export CLUSTER_STATIC_PEER_IP=example-peer
  export CLUSTER_PEER_STATE_PORT=18080
  export CLUSTER_PEER_STATE_TIMEOUT_SECS=2
  export CLUSTER_SOFTWARE_JSON='{"nix_ai":"nix-rev","mlx":"mlx-ver","mlx_lm":"mlx-lm-ver","macos":"","model":"example/model","model_revision":""}'
  export CLUSTER_SCHEDULE_NIGHT_START_MIN=1380
  export CLUSTER_SCHEDULE_DAY_START_MIN=420
  export CLUSTER_SCHEDULE_SWAP_THRESHOLD_MB=8000
  # Tripwires: the preflight must never run these.
  export CLUSTER_QUIESCE_CMD="printf 'quiesce\n' >> '$CALLS'"
  export CLUSTER_RESTORE_CMD="printf 'restore\n' >> '$CALLS'"
  export CLUSTER_INVOKER=dev.mlx-cluster.schedule-nightly

  export FAKE_HHMM=0130
  export FAKE_PGREP_RC=1
  export FAKE_PD_HELD=0
  export FAKE_SWAP_USED_MB=100
  export FAKE_CURL_RC=0
  export FAKE_LOCAL_REV=rev-a
  export FAKE_MACOS=25F71
  export FAKE_PEER_JSON='{"armed":false,"armed_at":0,"configuration_revision":"rev-a","phase":"abort","session":"","software":{"nix_ai":"nix-rev","mlx":"mlx-ver","mlx_lm":"mlx-lm-ver","macos":"25F71","model":"example/model","model_revision":""}}'

  printf 'down\n' > "$CLUSTER_STATE_FILE"
  printf '{"armed":false}\n' > "$CLUSTER_PEER_STATE_FILE"

  # The clock is the only thing faked in the shell itself: the preflight asks
  # for +%H%M, and every other date call goes to the real command.
  date() {
    if [ "$#" -eq 1 ] && [ "$1" = +%H%M ]; then
      printf '%s\n' "$FAKE_HHMM"
      return 0
    fi
    command date "$@"
  }

  local layer
  for layer in cluster-rank-status cluster-pd-count cluster-pd-gate cluster-schedule-common cluster-schedule-preflight; do
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

# Runs the preflight with the state files stamped in the past, so any write during
# the run shows up as a newer mtime.
run_preflight() {
  touch -t 200001010000 "$CLUSTER_STATE_FILE" "$CLUSTER_PEER_STATE_FILE"
  touch "$MARKER"
  run schedule_preflight_main
}

# No quiesce, restore, kickstart or bootout call, and no write to link-state or to
# the peer state file.
assert_no_side_effects() {
  [ ! -s "$CALLS" ]
  [ ! "$CLUSTER_STATE_FILE" -nt "$MARKER" ]
  [ ! "$CLUSTER_PEER_STATE_FILE" -nt "$MARKER" ]
}

@test 'outside the night window holds before any other guard runs' {
  export FAKE_HHMM=1200
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N0 decision=hold reason=outside-night-window'* ]]
  [[ "$output" != *'guard=N1'* ]]
  assert_no_side_effects
}

@test 'a window that starts and ends at the same minute holds as unconfigured' {
  export CLUSTER_SCHEDULE_DAY_START_MIN=1380
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N0 decision=hold reason=window-unconfigured'* ]]
  assert_no_side_effects
}

@test 'a live rank holds as already clustered' {
  export FAKE_PGREP_RC=0
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N1 decision=hold reason=already-clustered'* ]]
  assert_no_side_effects
}

@test 'an up link with this host armed holds as already clustered' {
  printf 'up\n' > "$CLUSTER_STATE_FILE"
  printf '{"armed":true}\n' > "$CLUSTER_PEER_STATE_FILE"
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N1 decision=hold reason=already-clustered'* ]]
  assert_no_side_effects
}

@test 'an unanswerable rank probe holds' {
  export FAKE_PGREP_RC=2
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N1 decision=hold reason=rank-probe-unanswerable'* ]]
  assert_no_side_effects
}

@test 'an unreachable peer holds' {
  export FAKE_CURL_RC=7
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N2 decision=hold reason=peer-unreachable'* ]]
  assert_no_side_effects
}

@test 'an armed peer holds' {
  export FAKE_PEER_JSON='{"armed":true,"armed_at":1,"configuration_revision":"rev-a","software":{"nix_ai":"nix-rev","mlx":"mlx-ver","mlx_lm":"mlx-lm-ver","macos":"25F71","model":"example/model","model_revision":""}}'
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N2 decision=hold reason=peer-armed'* ]]
  assert_no_side_effects
}

@test 'a peer on a different configuration generation holds' {
  export FAKE_PEER_JSON='{"armed":false,"configuration_revision":"rev-b","software":{"nix_ai":"nix-rev","mlx":"mlx-ver","mlx_lm":"mlx-lm-ver","macos":"25F71","model":"example/model","model_revision":""}}'
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N2 decision=hold reason=generation-mismatch'* ]]
  assert_no_side_effects
}

@test 'a mismatched pinned software key holds' {
  export FAKE_PEER_JSON='{"armed":false,"configuration_revision":"rev-a","software":{"nix_ai":"other-rev","mlx":"mlx-ver","mlx_lm":"mlx-lm-ver","macos":"25F71","model":"example/model","model_revision":""}}'
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N2 decision=hold reason=version-mismatch'* ]]
  assert_no_side_effects
}

@test 'an unpublished peer generation defers to the join instead of holding' {
  export FAKE_PEER_JSON='{"armed":false,"configuration_revision":"","software":{"nix_ai":"nix-rev","mlx":"mlx-ver","mlx_lm":"mlx-lm-ver","macos":"25F71","model":"example/model","model_revision":""}}'
  run_preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *'guard=N2 decision=pass reason=generation-deferred'* ]]
  assert_no_side_effects
}

@test 'a protection-domain reserve reached holds' {
  export FAKE_PD_HELD=7
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N3 decision=hold reason=pd-reserve'* ]]
  assert_no_side_effects
}

@test 'swap over the threshold holds' {
  export FAKE_SWAP_USED_MB=9000
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *'guard=N3 decision=hold reason=swap-over-threshold'* ]]
  assert_no_side_effects
}

@test 'every guard passing exits 0 and changes nothing' {
  run_preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *'guard=N0 decision=pass reason=in-night-window'* ]]
  [[ "$output" == *'guard=N1 decision=pass reason=not-clustered'* ]]
  [[ "$output" == *'guard=N2 decision=pass reason=generation-match'* ]]
  [[ "$output" == *'guard=N3 decision=pass reason=pd-reserve-available'* ]]
  [[ "$output" == *'preflight decision=pass'* ]]
  assert_no_side_effects
}
