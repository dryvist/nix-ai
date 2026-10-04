#!/usr/bin/env bash
# THE CHECK THAT FAILS IF A TEARDOWN CAN REPORT SUCCESS OVER A HOST THAT IS
# SERVING NOTHING.
#
# cluster-detach on the WORKER can print
#
#   cluster-detach: teardown verified (markers clear, rank gone, standalone
#                   ceiling restored)
#
# and exit 0, while the agents cluster-quiesce had booted out — the model
# server and its warmup among them — were still booted out and the endpoint
# answered connection-refused. Every statement in that line was true. The machine
# was serving nothing. The cause was structural: the restore lived in TWO places,
# a shared coordinator-and-worker helper used by the watcher, and a
# coordinator-only copy of half of it inside cluster-detach.
#
# So this file pins both halves:
#   BEHAVIOUR — restore_normal_serving, the now-single definition, sourced from
#               the shipped layer and driven through both roles and every failure
#               mode, including the one that used to `return 0` silently.
#   CALL SITE — cluster-detach.sh really calls it, and really probes serving for
#               BOTH roles. A correct function nobody calls passes every
#               behavioural assertion while the defect is fully back — the same
#               reason lib/checks/mlx-cluster-pd-callsites.nix exists.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — restore_normal_serving.
#   STUB  — launchctl (a fake on PATH, recording every verb) and the worker's
#           restore hook (a shell command whose exit code the test chooses).
#
# Usage:
#   RESTORE=/path/to/cluster-serving-restore.sh \
#   DETACH=/path/to/cluster-detach.sh bash test-serving-restore.sh
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# `#!/usr/bin/env bash` does not resolve in a Linux nix build sandbox; $BASH is
# the running interpreter's own absolute path, correct there and on a
# workstation alike (same fix as tests/test-peer-liveness.sh).
shebang="#!$BASH"

mkdir -p "$tmp/bin"
{
  printf '%s\n' "$shebang"
  cat << 'FAKE'
printf '%s\n' "$*" >> "$FAKE_DIR/launchctl.log"
# Independent loaded-markers: both resident agents and the watchdog are booted
# out and restored separately, so a stub that could not tell them apart would
# pass every assertion whether or not the real code told them apart either.
# print only carries the label; bootstrap only carries the plist path.
case "${1:-}" in
  print)
    label="${2##*/}"
    if [ "$label" = "${CLUSTER_WATCHDOG_LABEL:-__unset__}" ]; then
      [ -f "$FAKE_DIR/watchdog-loaded" ]
    else
      [ -f "$FAKE_DIR/$label.loaded" ]
    fi
    ;;
  bootstrap)
    label="${3##*/}"
    label="${label%.plist}"
    if [ "$label" = "${CLUSTER_WATCHDOG_LABEL:-__unset__}" ]; then
      [ "${FAKE_WATCHDOG_BOOTSTRAP_FAILS:-0}" = 1 ] && exit 1
      touch "$FAKE_DIR/watchdog-loaded"
    else
      [ "${FAKE_BOOTSTRAP_FAILS:-0}" = 1 ] && exit 1
      touch "$FAKE_DIR/$label.loaded"
    fi
    ;;
  *) exit 0 ;;
esac
FAKE
} > "$tmp/bin/launchctl"
chmod +x "$tmp/bin/launchctl"
PATH="$tmp/bin:$PATH"
export PATH
export FAKE_DIR="$tmp"

# shellcheck disable=SC1090
source "${RESTORE:?set RESTORE to the path of cluster-serving-restore.sh}"

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
launchctl_log() { cat "$tmp/launchctl.log" 2> /dev/null || true; }
did() {
  local label="$1" needle="$2"
  case "$(launchctl_log)" in
    *"$needle"*) echo "  ok   $label" ;;
    *)
      echo "  FAIL $label -> no '$needle' in launchctl log: $(launchctl_log | tr '\n' '|')"
      fail=1
      ;;
  esac
}
did_not() {
  local label="$1" needle="$2"
  case "$(launchctl_log)" in
    *"$needle"*)
      echo "  FAIL $label -> unexpected '$needle' in launchctl log"
      fail=1
      ;;
    *) echo "  ok   $label" ;;
  esac
}
reset_state() {
  : > "$tmp/launchctl.log"
  rm -f "$tmp"/*.loaded "$tmp/watchdog-loaded" "$tmp/restore-ran"
  unset FAKE_BOOTSTRAP_FAILS FAKE_WATCHDOG_BOOTSTRAP_FAILS
}

export CLUSTER_SERVER_LABELS="dev.example.server dev.example.server.mimo"
export CLUSTER_LAUNCH_AGENTS_DIR="$tmp/LaunchAgents"
mkdir -p "$CLUSTER_LAUNCH_AGENTS_DIR"
: > "$CLUSTER_LAUNCH_AGENTS_DIR/dev.example.server.plist"
: > "$CLUSTER_LAUNCH_AGENTS_DIR/dev.example.server.mimo.plist"
export CLUSTER_WATCHDOG_LABEL=dev.example.watchdog
export CLUSTER_WATCHDOG_PLIST="$tmp/watchdog.plist"
: > "$CLUSTER_WATCHDOG_PLIST"

echo "stub contract (everything below reaches launchctl only through this):"
reset_state
launchctl print gui/0/anything && loaded=0 || loaded=1
check "print fails while the agent is not loaded" 1 "$loaded"
launchctl bootstrap gui/0 "$CLUSTER_LAUNCH_AGENTS_DIR/dev.example.server.plist"
launchctl print gui/0/dev.example.server && loaded=0 || loaded=1
check "print succeeds after a bootstrap" 0 "$loaded"

echo
echo "coordinator: every booted-out resident agent is bootstrapped:"
reset_state
export CLUSTER_ROLE=coordinator
restore_normal_serving && rc=0 || rc=1
check "restore reports success" 0 "$rc"
did "bootstrapped the default resident" "bootstrap gui/$(id -u) $CLUSTER_LAUNCH_AGENTS_DIR/dev.example.server.plist"
did "bootstrapped the second resident" "bootstrap gui/$(id -u) $CLUSTER_LAUNCH_AGENTS_DIR/dev.example.server.mimo.plist"
did "bootstrapped the watchdog agent" "bootstrap gui/$(id -u) $CLUSTER_WATCHDOG_PLIST"

echo
echo "coordinator: already-loaded residents and watchdog are not re-bootstrapped:"
reset_state
touch "$tmp/dev.example.server.loaded" "$tmp/dev.example.server.mimo.loaded" "$tmp/watchdog-loaded"
restore_normal_serving && rc=0 || rc=1
check "restore reports success" 0 "$rc"
did_not "no redundant bootstrap" "bootstrap gui"

echo
echo "coordinator: a bootstrap that FAILS is a failure, not a shrug:"
reset_state
export FAKE_BOOTSTRAP_FAILS=1
restore_normal_serving && rc=0 || rc=1
check "restore reports failure" 1 "$rc"

echo
echo "coordinator: a missing resident plist is a failure:"
reset_state
rm "$CLUSTER_LAUNCH_AGENTS_DIR/dev.example.server.mimo.plist"
restore_normal_serving && rc=0 || rc=1
check "restore reports failure" 1 "$rc"
: > "$CLUSTER_LAUNCH_AGENTS_DIR/dev.example.server.mimo.plist"

echo
echo "coordinator: THE HAZARD. cluster-join also boots the watchdog out, and its"
echo "restore must be wired the same as the resident agents':"
# Confirmed at cluster-join.sh: the coordinator's quiesce step boots the
# watchdog out alongside the resident agents, so it must come back
# the same way -- left down, its next 60s probe finds "up but not serving"
# (indistinguishable from a real outage) and climbs its own escalation ladder,
# which can reach a full bootstrap of the standalone stack mid-cluster-window.
reset_state
touch "$tmp/dev.example.server.loaded" "$tmp/dev.example.server.mimo.loaded" # residents already up; isolate the watchdog assertion below
restore_normal_serving && rc=0 || rc=1
check "restore reports success" 0 "$rc"
did "bootstrapped the watchdog agent" "bootstrap gui/$(id -u) $CLUSTER_WATCHDOG_PLIST"

echo
echo "coordinator: the watchdog's OWN bootstrap failure is a WARN, not a restore"
echo "failure -- standalone serving is already back; the watchdog is a missing"
echo "safety net, not a repeat of the outage this function fixes:"
reset_state
touch "$tmp/dev.example.server.loaded" "$tmp/dev.example.server.mimo.loaded"
export FAKE_WATCHDOG_BOOTSTRAP_FAILS=1
restore_normal_serving && rc=0 || rc=1
check "restore STILL reports success" 0 "$rc"
unset FAKE_WATCHDOG_BOOTSTRAP_FAILS

echo
echo "coordinator: a watchdog with no plist and not loaded is the same WARN, not"
echo "a restore failure:"
reset_state
touch "$tmp/dev.example.server.loaded" "$tmp/dev.example.server.mimo.loaded"
CLUSTER_WATCHDOG_PLIST="$tmp/missing-watchdog.plist"
restore_normal_serving && rc=0 || rc=1
check "restore STILL reports success" 0 "$rc"
CLUSTER_WATCHDOG_PLIST="$tmp/watchdog.plist"

echo
echo "coordinator: an older generation with no CLUSTER_WATCHDOG_LABEL configured"
echo "is a clean no-op, not a failure -- nothing attempts to touch a label that"
echo "does not exist in the environment:"
reset_state
touch "$tmp/dev.example.server.loaded" "$tmp/dev.example.server.mimo.loaded"
unset CLUSTER_WATCHDOG_LABEL
restore_normal_serving && rc=0 || rc=1
check "restore reports success" 0 "$rc"
did_not "no watchdog bootstrap attempted" "bootstrap gui/$(id -u) $CLUSTER_WATCHDOG_PLIST"
export CLUSTER_WATCHDOG_LABEL=dev.example.watchdog

echo
echo "worker: the recorded agent set is restored through the quiesce's own hook:"
# cluster-restore bootstraps back EXACTLY what cluster-quiesce wrote down, which
# is why detach must call this rather than name agents itself.
reset_state
export CLUSTER_ROLE=worker
export CLUSTER_RESTORE_CMD="touch '$tmp/restore-ran'"
restore_normal_serving && rc=0 || rc=1
check "restore reports success" 0 "$rc"
check "the restore hook actually ran" present \
  "$([ -f "$tmp/restore-ran" ] && echo present || echo absent)"

echo
echo "worker: a PARTIAL restore is propagated as a failure:"
# cluster-restore keeps the labels it could not bootstrap and exits nonzero
# precisely so a later tick retries them. Swallowing that is how a half-restored
# host reports green.
reset_state
export CLUSTER_RESTORE_CMD="exit 1"
restore_normal_serving && rc=0 || rc=1
check "restore reports failure" 1 "$rc"

echo
echo "THE DEFECT: a worker that QUIESCES but cannot restore must not report success:"
# This is the exact shape of the 86-hour report. The old code fell off the end of
# an if/elif with status 0, so "there is nothing I can do" and "I restored
# serving" were the same answer.
reset_state
unset CLUSTER_RESTORE_CMD
export CLUSTER_QUIESCE_CMD="true"
restore_normal_serving && rc=0 || rc=1
check "restore reports failure" 1 "$rc"

echo
echo "...but a worker that quiesces NOTHING has nothing to restore, and passes:"
# The distinction matters: collapsing it into a failure would make the watcher
# hold the link-state edge forever on a host that was never quiesced, re-running
# a teardown every tick. Success here means the requested end state holds, not
# that the request was ignored.
reset_state
unset CLUSTER_RESTORE_CMD CLUSTER_QUIESCE_CMD
restore_normal_serving && rc=0 || rc=1
check "restore reports success" 0 "$rc"

echo
echo "call sites in cluster-detach.sh (a function nobody calls fixes nothing):"
detach="${DETACH:?set DETACH to the path of cluster-detach.sh}"
# Code lines only: the file's comments legitimately quote the old behaviour.
code() { grep -v '^[[:space:]]*#' "$detach"; }
pin() {
  local label="$1" pattern="$2"
  if grep -Eq "$pattern" <<< "$(code)"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label -> no code line matching /$pattern/"
    fail=1
  fi
}
anti_pin() {
  local label="$1" pattern="$2"
  if grep -Eq "$pattern" <<< "$(code)"; then
    echo "  FAIL $label -> code line matching /$pattern/ is back"
    fail=1
  else
    echo "  ok   $label"
  fi
}
pin "detach calls the shared restore" '(^|[^_[:alnum:]])restore_normal_serving'
pin "a failed restore is recorded as a failure" 'note_fail .*(restore|serving)'
pin "the real-completion probe is gated on the probe URL, not on the role" \
  '\[ -n "\$\{CLUSTER_STANDALONE_PROBE_URL'
pin "an unverifiable restore is a failure, never a pass" \
  'note_fail .*CLUSTER_STANDALONE_PROBE_URL'
anti_pin "the probe is no longer coordinator-only" \
  'if \[ "\$CLUSTER_ROLE" = "coordinator" \][^;]*; then$'
anti_pin "no line claims a bare 'teardown verified' any more" \
  'echo "cluster-detach: teardown verified'

echo
echo "call sites in cluster-join.sh (the watchdog boot-out this restore answers):"
join="${JOIN:?set JOIN to the path of cluster-join.sh}"
join_code() { grep -v '^[[:space:]]*#' "$join"; }
pin_join() {
  local label="$1" pattern="$2"
  if grep -Eq "$pattern" <<< "$(join_code)"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label -> no code line matching /$pattern/"
    fail=1
  fi
}
pin_join "join boots the watchdog out alongside the resident agents" \
  'bootout "gui/\$uid/\$\{CLUSTER_WATCHDOG_LABEL\}"'
pin_join "the boot-out is logged, including the unconfigured branch" \
  'CLUSTER_WATCHDOG_LABEL configured; nothing to boot out'

exit "$fail"
