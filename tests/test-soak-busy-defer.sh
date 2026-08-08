#!/usr/bin/env bash
# Exercises the soak re-check's queue-awareness — the guard that stops the
# health gate killing a busy-but-healthy pipeline.
#
# THE INCIDENT THIS PINS (2026-08-08). The soak fired its 1-token probe while a
# real 22k-token generation held the single pipeline slot and had streamed
# nothing for 181s. mlx_lm.server serializes generation and blocks HTTP, so the
# probe queued behind that request and expired on its own 120s timeout. The gate
# declared the rank wedged, SIGTERMed it, and the teardown leaked the wired
# shard on both hosts — a dual reboot, caused by probing a pipeline that was
# demonstrably alive and answering.
#
# Two properties, and they pull against each other, which is the whole design:
# in-flight work is proof of life so the probe must be DEFERRED, and a wedged
# rank holds connections open exactly as a busy one does so the deferral must be
# BOUNDED. Also pinned: the warm marker is not refreshed on a deferral, because
# refreshing it would push the next re-check a full interval away on every skip
# and let a permanently-connected wedge escape probing entirely.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL   — endpoint_busy, sourced from the shipped cluster-link-helpers.sh and
#            reading a stubbed netstat, exactly as the watcher calls it.
#   STUB   — netstat as a generated executable on CLUSTER_NETSTAT_BIN (the same
#            seam test-peer-rendezvous-session.sh uses), and
#            health_gate_soak_probe as a call-counting shell function, so the
#            assertion is "was the probe fired" rather than a real HTTP round
#            trip.
#   MIRROR — soak_tick below reproduces ONLY the watcher's soak decision
#            skeleton, because the watcher body also pings and calls launchctl
#            at import time. The skeleton is the branch under test; keep it in
#            step with cluster-link-watcher.sh.
#
# Usage:
#   HELPERS=/path/to/cluster-link-helpers.sh bash test-soak-busy-defer.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

warm_file="$state_dir/rank-warmed"
soak_busy_skips_file="$state_dir/soak-busy-skips"

export CLUSTER_HTTP_PORT=11440
export CLUSTER_SOAK_BUSY_SKIP_MAX=3

# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to cluster-link-helpers.sh}"

# --- netstat stub, generated executable ------------------------------------
bin="$state_dir/bin"
mkdir -p "$bin"
netstat_fixture="$state_dir/netstat-output"
# Shebang is the RUNNING bash's own path, never /usr/bin/env: the Nix build
# sandbox has no /usr/bin, so an env shebang leaves the stub unexecutable — and
# a netstat that cannot run returns nothing, which endpoint_busy reads as "no
# connection". The stub would then silently invert every case below instead of
# failing. Same idiom test-health-gate.sh uses for its vm_stat stub.
cat > "$bin/netstat" << NETSTAT
#!$BASH
cat '$netstat_fixture'
NETSTAT
chmod +x "$bin/netstat"
export CLUSTER_NETSTAT_BIN="$bin/netstat"

# netstat prints the port BEFORE the state, which is why endpoint_busy's awk is
# order-independent; the fixture keeps the real column order so a naive rewrite
# of that awk fails here.
set_busy() {
  if [ "$1" = yes ]; then
    printf 'tcp4 0 0 127.0.0.1.11440 127.0.0.1.51234 ESTABLISHED\n' > "$netstat_fixture"
  else
    printf 'tcp4 0 0 127.0.0.1.11440 *.* LISTEN\n' > "$netstat_fixture"
  fi
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# PROVE THE STUB WORKS BEFORE TRUSTING ANY VERDICT BUILT ON IT. A stub that
# cannot execute produces no output, endpoint_busy reads that as "nothing in
# flight", and every deferral case below then passes for the wrong reason —
# the silently-inert-guard shape this whole subsystem keeps shipping. Checked
# here so the failure names the stub rather than the behaviour under test.
set_busy yes
endpoint_busy || fail "the netstat stub is not executable — endpoint_busy cannot see a connection that is definitely there, so nothing below would be testing what it claims"
set_busy no
endpoint_busy && fail "the netstat stub reports a connection when the fixture has none"

# --- the probe, stubbed to count calls and replay a verdict -----------------
# The count lives in a FILE, not a variable: soak_tick is invoked in a command
# substitution so its assertions can read the outcome, and a subshell's variable
# writes never reach the parent — a counter kept in a variable would read 0
# forever and every "the probe did not fire" assertion would pass vacuously.
probe_calls_file="$state_dir/probe-calls"
printf '0\n' > "$probe_calls_file"
probe_rc=0
health_gate_soak_probe() {
  printf '%s\n' "$(($(cat "$probe_calls_file") + 1))" > "$probe_calls_file"
  return "$probe_rc"
}
probe_calls() { cat "$probe_calls_file"; }
reset_probe_calls() { printf '0\n' > "$probe_calls_file"; }

# --- MIRROR of the watcher's soak decision skeleton -------------------------
# Prints the outcome so each case can assert on it. halted is where the watcher
# SIGTERMs the rank and tears the cluster down.
soak_tick() {
  local soak_skips=0
  [ -f "$soak_busy_skips_file" ] && soak_skips="$(cat "$soak_busy_skips_file")"
  case "$soak_skips" in
    '' | *[!0-9]*) soak_skips=0 ;;
  esac
  if endpoint_busy && [ "$soak_skips" -lt "${CLUSTER_SOAK_BUSY_SKIP_MAX:-10}" ]; then
    soak_skips=$((soak_skips + 1))
    printf '%s\n' "$soak_skips" > "$soak_busy_skips_file"
    echo skipped
  elif health_gate_soak_probe; then
    touch "$warm_file"
    rm -f "$soak_busy_skips_file"
    echo passed
  else
    echo halted
  fi
}

# --- 1. a request in flight defers the probe --------------------------------
set_busy yes
rm -f "$warm_file" "$soak_busy_skips_file"
[ "$(soak_tick)" = skipped ] || fail "a request in flight must defer the probe"
[ "$(probe_calls)" -eq 0 ] || fail "the probe must not be fired at a busy pipeline"
[ ! -f "$warm_file" ] \
  || fail "a deferral must NOT refresh the warm marker — that would push the next re-check away on every skip and let a permanently-connected wedge escape probing"
[ "$(cat "$soak_busy_skips_file")" = 1 ] || fail "a deferral must be counted"

# The 2026-08-08 shape end to end: the probe would have FAILED had it run, and
# the pipeline was healthy. Deferring is what keeps the rank alive.
probe_rc=1
[ "$(soak_tick)" = skipped ] || fail "a busy pipeline must be deferred, not halted"
[ "$(probe_calls)" -eq 0 ] || fail "no probe may reach a busy pipeline before the bound"

# --- 2. the bound ends the deferral -----------------------------------------
# Still busy, but the deferrals are spent: a wedged rank holds connections open
# exactly as a busy one does, so the probe must eventually fire regardless.
probe_rc=1
[ "$(soak_tick)" = skipped ] || fail "the third deferral is still within the bound"
[ "$(cat "$soak_busy_skips_file")" = 3 ] || fail "the counter must reach the bound"
[ "$(soak_tick)" = halted ] \
  || fail "at the bound the probe must fire regardless — otherwise a wedge that holds a connection is never probed"
[ "$(probe_calls)" -eq 1 ] || fail "exactly one probe fires at the bound"

# --- 3. a passing probe resets the deferral budget --------------------------
probe_rc=0
reset_probe_calls
printf '2\n' > "$soak_busy_skips_file"
set_busy no
[ "$(soak_tick)" = passed ] || fail "an idle pipeline must be probed normally"
[ "$(probe_calls)" -eq 1 ] || fail "the probe must fire when nothing is in flight"
[ -f "$warm_file" ] || fail "a passing probe refreshes the warm marker"
[ ! -f "$soak_busy_skips_file" ] \
  || fail "a passing probe must reset the deferral budget, so the next busy spell gets its full allowance"

# --- 4. an idle pipeline that fails still halts -----------------------------
# The guard defers probes, it does not weaken them. A rank with nothing in
# flight that cannot answer is exactly what the soak exists to catch.
probe_rc=1
rm -f "$soak_busy_skips_file"
[ "$(soak_tick)" = halted ] || fail "an idle rank that fails its probe must still halt"

echo "PASS: soak defers to in-flight work, bounds the deferral, and still halts a genuinely dead rank"
