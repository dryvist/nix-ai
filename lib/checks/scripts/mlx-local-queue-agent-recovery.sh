#!/usr/bin/env bash
# Test body for the mlx-local-queue-agent-recovery check
# (lib/checks/mlx-local-queue.nix). Extracted to its own file per this repo's
# inline-script policy for .nix files. HAPROXY_CFG, AGENT_PORT, METRICS_URL,
# LIVE_AGENT and BARE_READY_AGENT are set by the calling derivation; $out
# comes from the Nix build env.
#
# HAProxy runs the rendered local-queue config (agent-check only, no `check`)
# against a power agent that socat serves one connection at a time, exactly as
# launchd serves the real one. The power state the agent reads is a file, so
# the cycle AC -> battery -> AC is driven from here.
#
# A server only returns to UP when the agent reply contains `up`; `ready`
# merely cancels maintenance and leaves the server DOWN. So:
#   LIVE_AGENT       the launchd agent's own command -> UP, MAINT, UP
#   BARE_READY_AGENT the same command replying a bare `ready` -> UP, MAINT,
#                    DOWN. This is the negative fixture: it proves the cycle
#                    can tell a recovering agent from a non-recovering one.
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"
export PMSET_STATE="$TMPDIR/pmset-state"

# The agent command reads the power source from `pmset`'s output.
power() { echo "Now drawing from '$1 Power'" >"$PMSET_STATE"; }

# Every server's state, read from HAProxy's own metrics endpoint; empty until
# HAProxy is listening.
states() {
  { curl -sf "$METRICS_URL" || true; } |
    sed -n 's/^haproxy_server_status{.*state="\([A-Z]*\)"} 1$/\1/p' |
    sort -u | tr '\n' ' '
}

await() {
  for _ in $(seq 20); do
    if [ "$(states)" = "$1 " ]; then
      echo "all servers $1"
      return 0
    fi
    sleep 0.5
  done
  echo "servers never reached $1 (last: $(states))" >&2
  return 1
}

# cycle <agent script> <final state>: serve the agent, start HAProxy, then
# AC -> battery -> AC. Both children are reaped on exit by their own PIDs.
cycle() (
  power AC
  socat "TCP-LISTEN:$AGENT_PORT,bind=127.0.0.1,reuseaddr,fork" "EXEC:sh $1" &
  agent=$!
  haproxy -db -f "$HAPROXY_CFG" &
  proxy=$!
  trap 'kill "$agent" "$proxy" || true; wait' EXIT
  await UP && power Battery && await MAINT && power AC && await "$2"
)

echo "power agent as shipped: AC -> battery -> AC must end UP"
cycle "$LIVE_AGENT" UP

echo "power agent replying a bare ready: must end DOWN, never UP"
cycle "$BARE_READY_AGENT" DOWN

touch "$out"
