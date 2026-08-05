#!/usr/bin/env bash
# Exercises mlx_reap_orphan_ports (and its helpers) from
# modules/mlx/scripts/llama-swap-reap.sh — the port-ownership reap that
# replaced llama-swap-launch.sh's process-pattern reap.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — mlx_reap_ports / mlx_port_holders / mlx_reap_orphan_ports are
#           sourced from the shipped script and called exactly as
#           llama-swap-launch.sh calls them.
#   STUB  — lsof and kill, via the MLX_LSOF_BIN / MLX_KILL_BIN env seam the
#           functions already expose (writeShellApplication's sanitized PATH
#           has neither on Darwin, and the Linux CI runner has no port
#           ownership to inspect in the first place). The fakes are backed by
#           one file per port under $STATE_DIR, so a kill call can actually
#           make a later lsof query come back empty — the real reap-then-
#           recheck loop depends on that feedback.
#   STUB  — sleep, overridden as a shell function (same trick as
#           tests/test-rank-start-guards.sh) so the 10x1s graceful window and
#           the 2s post-SIGKILL settle run instantly instead of ~12s real time.
#
# Replays the 2026-07-26 incident directly: a 94-minute-old orphan holding the
# worker port survived a proxy restart because the OLD reap matched processes
# by MLX_MODEL_SERVER_PROCESS_PATTERN, and that pattern never matched the
# in-process mlx-lm-launch.py worker shape (see llama-swap-reap.sh's header
# for the confirmed-live evidence). This fails if a port-holding orphan is not
# reaped, and fails if anything outside our owned port block is ever touched.
set -o errexit -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
reap_script="$repo_root/modules/mlx/scripts/llama-swap-reap.sh"

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
mkdir -p "$state_dir/bin"
kill_log="$state_dir/kill.log"
: > "$kill_log"

# $BASH, not /usr/bin/env: a Linux nix build sandbox has no /usr/bin/env, only
# /bin/sh — see tests/test-peer-liveness.sh for the same fix.
shebang="#!$BASH"

{
  printf '%s\n' "$shebang"
  cat << 'FAKE'
# fake lsof -ti ":<port>" -> the pid recorded at $STATE_DIR/port-<port>, if any.
port="${2#:}"
port_file="$STATE_DIR/port-$port"
[ -f "$port_file" ] || exit 1
cat "$port_file"
exit 0
FAKE
} > "$state_dir/bin/fake-lsof"
chmod +x "$state_dir/bin/fake-lsof"

{
  printf '%s\n' "$shebang"
  cat << 'FAKE'
# fake kill -TERM|-KILL <pid> -> logs the call, then clears every port file
# bound to that pid UNLESS it is marked immortal (survives everything) or
# stubborn-to-TERM (only SIGKILL clears it).
sig="$1"
pid="$2"
printf '%s %s\n' "$sig" "$pid" >> "$STATE_DIR/kill.log"
[ -f "$STATE_DIR/immortal-$pid" ] && exit 0
stubborn=0
[ -f "$STATE_DIR/stubborn-$pid" ] && stubborn=1
if [ "$sig" = "-KILL" ] || [ "$stubborn" -eq 0 ]; then
  for f in "$STATE_DIR"/port-*; do
    [ -f "$f" ] || continue
    [ "$(cat "$f")" = "$pid" ] && rm -f "$f"
  done
fi
exit 0
FAKE
} > "$state_dir/bin/fake-kill"
chmod +x "$state_dir/bin/fake-kill"

export STATE_DIR="$state_dir"
{
  printf '%s\n' "$shebang"
  cat << 'FAKE'
# fake ps -o ppid= -p <pid> -> the ppid recorded at $STATE_DIR/ppid-<pid>,
# defaulting to a real-looking parent. Only ppid 1 means "re-parented orphan";
# anything else is a live worker still under the llama-swap -> uv chain.
#
# The pid is $4, not $3: the invocation is `-o ppid= -p <pid>`, so
# $1=-o $2=ppid= $3=-p $4=<pid>. Reading $3 silently returned the default for
# every pid, which made the "orphan is reaped" cases look broken while the
# "live worker survives" cases passed for the wrong reason.
pid="$4"
ppid_file="$STATE_DIR/ppid-$pid"
if [ -f "$ppid_file" ]; then cat "$ppid_file"; else echo "  4242"; fi
exit 0
FAKE
} > "$state_dir/bin/fake-ps"
chmod +x "$state_dir/bin/fake-ps"

export MLX_LSOF_BIN="$state_dir/bin/fake-lsof"
export MLX_KILL_BIN="$state_dir/bin/fake-kill"
export MLX_PS_BIN="$state_dir/bin/fake-ps"
export MLX_PORT=11434
export MLX_WORKER_PORT_RANGE_START=11436
export MLX_WORKER_PORT_COUNT=2

# shellcheck disable=SC1090
source "$reap_script"

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

# The function's own port-ownership decisions are under test, not real time.
# mlx_reap_orphan_ports calls this indirectly during its graceful-window poll
# and its post-SIGKILL settle; asserted directly here too so it is genuinely
# invoked from this file's own scope, not just from the sourced function.
sleep() { :; }
check "sleep is stubbed (no real wait)" ok "$(sleep 5 && echo ok)"
reset_state() {
  rm -f "$state_dir"/port-* "$state_dir"/stubborn-* "$state_dir"/immortal-*
  : > "$kill_log"
}
signals_to() {
  grep -c -- " $1\$" "$kill_log" 2> /dev/null || true
}
exact_signal() {
  grep -cx -- "$1 $2" "$kill_log" 2> /dev/null || true
}
port_file_exists() {
  [ -f "$state_dir/port-$1" ] && echo 1 || echo 0
}

echo "nothing holding our ports is a true no-op:"
reset_state
rc=0
mlx_reap_orphan_ports || rc=$?
check "reap succeeds" 0 "$rc"
check "no kill issued at all" 0 "$(wc -l < "$kill_log" | tr -d ' ')"

echo "an orphan on a worker port that dies on SIGTERM is reaped:"
reset_state
printf '9101\n' > "$state_dir/port-11437"
rc=0
mlx_reap_orphan_ports || rc=$?
check "reap succeeds" 0 "$rc"
check "SIGTERM was sent to it" 1 "$(exact_signal -TERM 9101)"
check "no SIGKILL needed" 0 "$(exact_signal -KILL 9101)"
check "port file cleared" 0 "$(port_file_exists 11437)"

echo "an orphan on the proxy's own port that ignores SIGTERM is SIGKILL'd:"
reset_state
printf '9102\n' > "$state_dir/port-11434"
: > "$state_dir/stubborn-9102"
rc=0
mlx_reap_orphan_ports || rc=$?
check "reap succeeds" 0 "$rc"
check "SIGTERM was tried first" 1 "$(exact_signal -TERM 9102)"
check "escalated to SIGKILL" 1 "$(exact_signal -KILL 9102)"
check "port file cleared" 0 "$(port_file_exists 11434)"

echo "a holder that survives even SIGKILL fails loud (caller must not exec the proxy):"
reset_state
printf '9103\n' > "$state_dir/port-11436"
: > "$state_dir/immortal-9103"
rc=0
mlx_reap_orphan_ports || rc=$?
check "reap FAILS" 1 "$rc"
check "SIGKILL was still attempted" 1 "$(exact_signal -KILL 9103)"

echo "a holder OUTSIDE our port block is never touched:"
reset_state
printf '9104\n' > "$state_dir/port-15000"
printf '9101\n' > "$state_dir/port-11437"
rc=0
mlx_reap_orphan_ports || rc=$?
check "reap succeeds" 0 "$rc"
check "in-range orphan still reaped" 1 "$(exact_signal -TERM 9101)"
check "out-of-range holder never signalled" 0 "$(signals_to 9104)"
check "out-of-range port file untouched" 1 "$(port_file_exists 15000)"

# --- mlx_reap_reparented_only: safe to run while the proxy is SERVING --------
# mlx_reap_orphan_ports kills every holder, which is correct only at proxy
# start (nothing legitimate is bound yet). A time-triggered reaper needs to run
# while the proxy is up, so it must not touch the worker currently serving
# traffic. ppid is the discriminator: a live worker sits under the
# llama-swap -> uv -> python chain, so its ppid is never 1; an orphan was
# re-parented to launchd, so its ppid is exactly 1.

echo "a LIVE worker (real parent) is never reaped by the re-parented reaper:"
reset_state
printf '9101\n' > "$state_dir/port-11437"
printf '  4242\n' > "$state_dir/ppid-9101"
rc=0
mlx_reap_reparented_only || rc=$?
check "reap succeeds" 0 "$rc"
check "live worker never signalled" 0 "$(signals_to 9101)"
check "live worker still holds its port" 1 "$(port_file_exists 11437)"

echo "a RE-PARENTED orphan (ppid 1) is reaped:"
reset_state
printf '9101\n' > "$state_dir/port-11437"
printf '1\n' > "$state_dir/ppid-9101"
rc=0
mlx_reap_reparented_only || rc=$?
check "reap succeeds" 0 "$rc"
check "orphan got SIGTERM" 1 "$(exact_signal -TERM 9101)"
check "orphan port released" 0 "$(port_file_exists 11437)"

echo "a live worker beside an orphan: only the orphan dies:"
reset_state
printf '9101\n' > "$state_dir/port-11437"
printf '1\n' > "$state_dir/ppid-9101"
printf '9102\n' > "$state_dir/port-11438"
printf '  4242\n' > "$state_dir/ppid-9102"
rc=0
mlx_reap_reparented_only || rc=$?
check "reap succeeds" 0 "$rc"
check "orphan reaped" 1 "$(exact_signal -TERM 9101)"
check "live worker untouched" 0 "$(signals_to 9102)"
check "live worker keeps its port" 1 "$(port_file_exists 11438)"

echo "a re-parented orphan that ignores SIGTERM is escalated to SIGKILL:"
reset_state
printf '9101\n' > "$state_dir/port-11437"
printf '1\n' > "$state_dir/ppid-9101"
: > "$state_dir/stubborn-9101"
rc=0
mlx_reap_reparented_only || rc=$?
check "reap succeeds after escalation" 0 "$rc"
check "SIGTERM was tried first" 1 "$(exact_signal -TERM 9101)"
check "escalated to SIGKILL" 1 "$(exact_signal -KILL 9101)"
check "port finally released" 0 "$(port_file_exists 11437)"

echo "nothing bound at all is a no-op for the re-parented reaper too:"
reset_state
rc=0
mlx_reap_reparented_only || rc=$?
check "reap succeeds" 0 "$rc"
check "no kill issued" 0 "$(wc -l < "$kill_log" | tr -d ' ')"

exit "$fail"
