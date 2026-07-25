#!/usr/bin/env bash
# Exercises the peer-liveness state machine from
# modules/mlx/scripts/cluster-peer-liveness.sh through the sequences that
# matter: a healthy rank is never killed, a dead peer and a wedged peer are
# told apart, and recovery clears the accumulated state.
#
# Unlike tests/test-link-debounce.sh, this does NOT mirror the logic — it
# assembles the REAL script exactly as modules/mlx/peer-liveness.nix does
# (helpers concatenated ahead of the state machine) and runs it, with
# launchctl / curl / netstat / ping replaced by fakes on PATH. So it fails if
# the shipped script drifts, which the debounce test explicitly cannot do.
#
# What it still cannot prove, stated plainly: nothing here has been converged,
# so the fakes encode ASSUMPTIONS about the real world — that netstat renders a
# JACCL rendezvous session as an ESTABLISHED row carrying the peer IP and the
# rendezvous port, and that mlx_lm.server writes generation lines matching the
# default progress pattern. Both need one live cluster session to confirm.
set -o errexit -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_dir="$repo_root/modules/mlx/scripts"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Assemble the way the module does: helpers, observers, then the state machine,
# under writeShellApplication's shell flags.
{
  printf '#!/usr/bin/env bash\nset -o errexit -o nounset -o pipefail\n'
  cat "$script_dir/cluster-link-helpers.sh"
  cat "$script_dir/cluster-peer-observe.sh"
  cat "$script_dir/cluster-peer-liveness.sh"
} > "$tmp/peer-liveness.sh"
chmod +x "$tmp/peer-liveness.sh"

mkdir -p "$tmp/bin" "$tmp/state"

cat > "$tmp/bin/launchctl" << 'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_DIR/launchctl.log"
if [ "${1:-}" = "print" ] && [[ "${2:-}" == *"$FAKE_RANK_LABEL" ]]; then
  [ -f "$FAKE_DIR/rank-running" ] && echo "  state = running"
elif [ "${1:-}" = "kill" ]; then
  # A SIGTERM that lands: the rank stops, so the next rank_running is false.
  [ "${FAKE_RANK_IGNORES_SIGTERM:-0}" = "1" ] || rm -f "$FAKE_DIR/rank-running"
fi
exit 0
FAKE

cat > "$tmp/bin/curl" << 'FAKE'
#!/usr/bin/env bash
if [[ "$*" == *"/v1/chat/completions"* ]]; then
  echo probe >> "$FAKE_DIR/probe.log"
  if [ "${FAKE_PROBE_OK:-0}" = "1" ]; then
    printf '{"choices":[{"message":{"content":"x"}}],"usage":{"completion_tokens":1}}\n'
    exit 0
  fi
  # A 200 carrying an empty completion — the shape that fooled the operator.
  if [ "${FAKE_PROBE_EMPTY_200:-0}" = "1" ]; then
    printf '{"choices":[],"usage":{"completion_tokens":0}}\n'
    exit 0
  fi
  exit 28
fi
# One line per page, because the jq payload itself is pretty-printed across
# several lines and cannot be counted.
echo alert >> "$FAKE_DIR/alert-count"
prev=""
for a in "$@"; do
  [ "$prev" = "--data-binary" ] && printf '%s\n' "$a" >> "$FAKE_DIR/alerts.jsonl"
  prev="$a"
done
printf 'ok\n200'
FAKE

cat > "$tmp/bin/netstat" << 'FAKE'
#!/usr/bin/env bash
cat "$FAKE_DIR/netstat.out" 2> /dev/null || true
FAKE

cat > "$tmp/bin/ping" << 'FAKE'
#!/usr/bin/env bash
exit "${FAKE_PING_RC:-0}"
FAKE

chmod +x "$tmp/bin/"*
: > "$tmp/alert-url"
echo "https://hooks.example.invalid/x" > "$tmp/alert-url"

export FAKE_DIR="$tmp"
export FAKE_RANK_LABEL="dev.mlx-cluster.rank"
export PATH="$tmp/bin:$PATH"

export CLUSTER_RANK_LABEL="$FAKE_RANK_LABEL"
export CLUSTER_STATE_FILE="$tmp/state/link-state"
export CLUSTER_STATIC_PEER_IP="192.168.208.2"
export CLUSTER_RENDEZVOUS_PORT="11441"
export CLUSTER_HTTP_PORT="11440"
export CLUSTER_RANK_URL="http://127.0.0.1:11440"
export CLUSTER_MODEL="test/model"
export CLUSTER_RANK_LOGS="$tmp/rank.log $tmp/rank.error.log"
export CLUSTER_RANK_PROGRESS_LOG="$tmp/rank.error.log"
export CLUSTER_ALERT_URL_FILE="$tmp/alert-url"
export CLUSTER_WARMUP_LABEL="dev.mlx.warmup"
export CLUSTER_SERVER_LABEL="dev.mlx.server"
export CLUSTER_SERVER_PLIST="$tmp/server.plist"
export CLUSTER_NORMAL_PROXY="http://127.0.0.1:8080"
export CLUSTER_PING_BIN="$tmp/bin/ping"
export CLUSTER_NETSTAT_BIN="$tmp/bin/netstat"
# Rate limiting is proven by its own case; elsewhere every tick may probe.
export CLUSTER_PEER_PROBE_INTERVAL_SECS="0"
export CLUSTER_PEER_PROBE_TIMEOUT_SECS="1"
export CLUSTER_PEER_STRIKES="3"
export CLUSTER_PEER_DEAD_TICKS="3"

# netstat fixtures, in the macOS `netstat -an -p tcp` shape.
rendezvous_open=$'tcp4       0      0  192.168.208.1.11441    192.168.208.2.51422    ESTABLISHED\n'
rendezvous_gone=$'tcp4       0      0  192.168.208.1.11441    *.*                    LISTEN\n'
client_in_flight=$'tcp4       0      0  127.0.0.1.11440        127.0.0.1.62111        ESTABLISHED\n'

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

reset() {
  rm -rf "$tmp/state"
  mkdir -p "$tmp/state"
  rm -f "$tmp/launchctl.log" "$tmp/probe.log" "$tmp/alerts.jsonl" "$tmp/alert-count" "$tmp/netstat.out"
  : > "$tmp/rank.log"
  : > "$tmp/rank.error.log"
  echo up > "$tmp/state/link-state"
  touch "$tmp/state/rank-ready" "$tmp/rank-running"
  printf '%s' "$rendezvous_open" > "$tmp/netstat.out"
  export FAKE_PROBE_OK=0 FAKE_PROBE_EMPTY_200=0 FAKE_PING_RC=0 FAKE_RANK_IGNORES_SIGTERM=0
}

tick() { CLUSTER_ROLE="${1:-coordinator}" "$tmp/peer-liveness.sh" > "$tmp/tick.out" 2>&1 || true; }

torn_down() { [ -f "$tmp/state/rank-halted" ] && echo yes || echo no; }
probe_count() { grep -c probe "$tmp/probe.log" 2> /dev/null || echo 0; }
alert_text() { cat "$tmp/alerts.jsonl" 2> /dev/null || true; }
alert_says() { alert_text | grep -qF "$1" && echo yes || echo no; }
alert_count() { grep -c alert "$tmp/alert-count" 2> /dev/null || echo 0; }

echo "a healthy rank is never killed:"

reset
export FAKE_PROBE_OK=1
tick coordinator
tick coordinator
check "probe returns a token -> no teardown" no "$(torn_down)"

# Real traffic must short-circuit the probe entirely: a node under load is the
# node most likely to fail a timed probe, and the least deserving of a kill.
reset
printf 'Generation: 812 tokens, 41.2 tokens-per-sec\n' >> "$tmp/rank.error.log"
tick coordinator
check "token lines in the log -> no probe sent" 0 "$(probe_count)"
check "token lines in the log -> no teardown" no "$(torn_down)"

# The observed false-positive shape: mlx_lm.server blocks HTTP for the whole
# generation, so a probe fired while a client request is open would time out
# through no fault of the mesh.
reset
printf '%s%s' "$rendezvous_open" "$client_in_flight" > "$tmp/netstat.out"
tick coordinator
tick coordinator
tick coordinator
tick coordinator
check "client request in flight -> no probe sent" 0 "$(probe_count)"
check "client request in flight -> no teardown" no "$(torn_down)"

# Below the strike threshold nothing happens, however loud the failure.
reset
tick coordinator
tick coordinator
check "2 of 3 failed probes -> no teardown" no "$(torn_down)"
check "2 of 3 failed probes -> no page" "" "$(alert_text)"

echo
echo "a wedged peer is detected:"

reset
tick coordinator
tick coordinator
tick coordinator
check "3 failed probes -> torn down" yes "$(torn_down)"
check "cause names the wedge" yes "$(alert_says "peer rank is WEDGED")"
check "evidence records the open rendezvous" yes "$(alert_says "rendezvous=established")"
check "standalone serving re-warmed" yes "$(grep -q "kickstart -k gui/.*dev.mlx.warmup" "$tmp/launchctl.log" && echo yes || echo no)"

# A 200 with an empty completion is the exact failure that kept /v1/models
# looking healthy for 900s. HTTP status alone must never count as progress.
reset
export FAKE_PROBE_EMPTY_200=1
tick coordinator
tick coordinator
tick coordinator
check "200 with zero completion_tokens is NOT progress" yes "$(torn_down)"

echo
echo "a dead peer is detected and told apart from a wedged one:"

reset
printf '%s' "$rendezvous_gone" > "$tmp/netstat.out"
tick coordinator
tick coordinator
tick coordinator
check "3 failed probes -> torn down" yes "$(torn_down)"
check "cause names the dead peer rank" yes "$(alert_says "rendezvous session is GONE")"
check "evidence records the absent rendezvous" yes "$(alert_says "rendezvous=absent")"
check "not misreported as wedged" no "$(alert_says "peer rank is WEDGED")"

reset
export FAKE_PING_RC=1
printf '%s' "$rendezvous_gone" > "$tmp/netstat.out"
tick coordinator
tick coordinator
tick coordinator
check "peer unreachable -> named as host/link down" yes "$(alert_says "peer host or link is down")"

echo
echo "recovery clears the accumulated state:"

reset
tick coordinator
tick coordinator
check "2 strikes banked" 2 "$(cat "$tmp/state/peer-strikes")"
export FAKE_PROBE_OK=1
tick coordinator
check "a success clears the strike count" no "$([ -f "$tmp/state/peer-strikes" ] && echo yes || echo no)"
export FAKE_PROBE_OK=0
tick coordinator
tick coordinator
check "count restarted, so 2 more still hold" no "$(torn_down)"

# The link watcher owns the link edge; an unplug must leave nothing behind that
# would bias the next link session toward a teardown.
reset
tick coordinator
tick coordinator
echo down > "$tmp/state/link-state"
tick coordinator
check "link down wipes the strike count" no "$([ -f "$tmp/state/peer-strikes" ] && echo yes || echo no)"
check "link down -> no teardown" no "$(torn_down)"

echo
echo "the supervisor stands down where the watcher already owns the rank:"

reset
rm -f "$tmp/state/rank-ready"
tick coordinator
tick coordinator
tick coordinator
check "before readiness latches -> no probe" 0 "$(probe_count)"
check "before readiness latches -> no teardown" no "$(torn_down)"

reset
rm -f "$tmp/rank-running"
tick coordinator
tick coordinator
tick coordinator
check "rank not running -> left to the watcher's kickstart path" no "$(torn_down)"

reset
touch "$tmp/state/rank-halted"
tick coordinator
check "already halted -> no second probe" 0 "$(probe_count)"

# A rank that survives SIGTERM must NOT get the halt marker: the watcher clears
# that marker whenever it sees the rank running, so setting it over a live rank
# would hand the next watcher tick a rank to kickstart that was never stopped.
reset
export FAKE_RANK_IGNORES_SIGTERM=1
tick coordinator
tick coordinator
tick coordinator
check "rank ignored SIGTERM -> kickstarts not halted" no "$(torn_down)"
check "still paged" yes "$(alert_says "produced no token")"

echo
echo "the worker reports its own death, with the traceback:"

reset
rm -f "$tmp/rank-running"
cat >> "$tmp/rank.error.log" << 'LOG'
Traceback (most recent call last):
  File "mlx_lm/utils.py", line 536, in load_model
    raise ValueError(msg)
ValueError: The model does not support pipelining but a pipeline_group was provided
LOG
tick worker
tick worker
check "below deadTicks -> no page yet" "" "$(alert_text)"
tick worker
check "worker pages once its rank stays down" yes "$(alert_says "rank agent dev.mlx-cluster.rank is not running")"
check "the page carries the real cause" yes \
  "$(alert_says "ValueError: The model does not support pipelining")"
check "the page says the coordinator cannot see this" yes "$(alert_says "CANNOT see this")"

tick worker
check "one page per death episode" 1 "$(alert_count)"

touch "$tmp/rank-running"
tick worker
rm -f "$tmp/rank-running"
tick worker
tick worker
tick worker
check "a recovered-then-dead rank re-arms the page" 2 "$(alert_count)"

# The worker cannot see tokens (rank 1 never binds the endpoint), so it must
# never probe and must never tear the cluster down on its own.
reset
tick worker
tick worker
tick worker
check "worker never probes" 0 "$(probe_count)"
check "worker never tears down a running rank" no "$(torn_down)"

echo
echo "probe rate limiting holds:"

reset
CLUSTER_PEER_PROBE_INTERVAL_SECS=3600 tick coordinator
CLUSTER_PEER_PROBE_INTERVAL_SECS=3600 tick coordinator
CLUSTER_PEER_PROBE_INTERVAL_SECS=3600 tick coordinator
check "one probe per interval, not one per tick" 1 "$(probe_count)"

exit "$fail"
