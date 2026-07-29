# shellcheck shell=bash
# Cluster peer-liveness — observation predicates.
#
# Concatenated ahead of cluster-peer-liveness.sh by the module (split out for
# the per-file size cap, same shape as cluster-link-helpers.sh). Function
# definitions only: every one reads the CLUSTER_* env directly, resolved at
# call time, so nothing here depends on the state machine's bindings.
#
# WHAT COUNTS AS EVIDENCE, and what is actively misleading.
#
# CPU and process state are never consulted as health. While the mesh is
# deadlocked both ranks spin at ~100% CPU — one polling the RDMA completion
# queue, the other polling a Metal buffer — and launchctl reports
# `state = running` throughout. A supervisor built on either signal would have
# reported green through both observed outages.
#
# TOKENS are the only accepted proof of liveness: either produced by real
# traffic (new_progress_lines) or asked for directly (probe_tokens). An HTTP
# 200 is explicitly not enough — the 900s wedge answered /v1/models the whole
# time, and returned a completion with zero tokens in it.
#
# Consumed environment:
#   CLUSTER_STATE_FILE               watcher's link-state file; its directory is
#                                    the shared marker dir
#   CLUSTER_RANK_LABEL               launchd label of the cluster rank agent
#   CLUSTER_STATIC_PEER_IP           peer's static link address
#   CLUSTER_RENDEZVOUS_PORT          JACCL rendezvous port (peer evidence)
#   CLUSTER_HTTP_PORT                coordinator: endpoint port (in-flight check)
#   CLUSTER_RANK_URL                 coordinator: endpoint base URL for the probe
#   CLUSTER_MODEL                    coordinator: model id sent in the probe
#   CLUSTER_RANK_LOGS                space-separated rank logs to quote in a page
#   CLUSTER_RANK_PROGRESS_LOG        the one log token progress is counted from
#   CLUSTER_PEER_PROGRESS_PATTERN    ERE marking token progress in that log
#   CLUSTER_PEER_PROBE_TIMEOUT_SECS  timeout of one bounded probe
#   CLUSTER_PEER_LOG_TAIL_LINES      rank-log lines attached to a page
#   CLUSTER_PING_BIN CLUSTER_NETSTAT_BIN   test seams; production absolute paths

read_int() {
  local value=0
  [ -f "$1" ] && value="$(cat "$1")"
  case "$value" in
    '' | *[!0-9]*) value=0 ;;
  esac
  printf '%s' "$value"
}

link_up() { [ "$(cat "${CLUSTER_STATE_FILE}" 2> /dev/null || echo down)" = "up" ]; }

rank_running() {
  launchctl print "gui/$(id -u)/${CLUSTER_RANK_LABEL}" 2> /dev/null |
    grep -q "state = running"
}

# peer_reachable moved to cluster-link-helpers.sh for the same reason, and on
# the same day the link watcher gained a peer rung of its own: a rank started
# against a host that is not there fails rendezvous every time and leaks a
# protection domain doing it, so the watcher needs this probe too.
#
# peer_rendezvous_session moved to cluster-link-helpers.sh, which both this
# supervisor and the link watcher concatenate — the watcher now needs it too, and
# one definition beats two that can drift. Persistence across a full generation is
# measured there.

# A request is in flight when something holds an ESTABLISHED connection on the
# endpoint port. Probing then is how a HEALTHY busy rank gets killed:
# mlx_lm.server serializes generation and blocks HTTP for its duration, so the
# probe would queue behind the real request and time out through no fault of
# the mesh. Checked BEFORE the probe opens its own socket, so it never sees
# itself.
endpoint_busy() {
  [ -n "${CLUSTER_HTTP_PORT:-}" ] || return 1
  "${CLUSTER_NETSTAT_BIN:-/usr/sbin/netstat}" -an -p tcp 2> /dev/null |
    awk -v port=".${CLUSTER_HTTP_PORT}" '
      /ESTABLISHED/ && index($0, port) { found = 1 }
      END { exit(found ? 0 : 1) }'
}

# Tokens produced by REAL traffic since the last tick. Counts matches only in
# the bytes APPENDED since last time, so a hit is a true progress edge rather
# than a total that stops moving for ambiguous reasons — and it stays cheap on
# a log newsyslog lets grow to 10 MB. A shrunken file means newsyslog rotated
# it, so the offset restarts at zero instead of reading past the end forever.
new_progress_lines() {
  local f="${CLUSTER_RANK_PROGRESS_LOG:-}" offset_file size off
  { [ -n "$f" ] && [ -f "$f" ]; } || {
    printf '0'
    return 0
  }
  offset_file="$(dirname "${CLUSTER_STATE_FILE}")/peer-progress-offset"
  size="$(/usr/bin/stat -f %z "$f" 2> /dev/null || wc -c < "$f")"
  off="$(read_int "$offset_file")"
  [ "$size" -lt "$off" ] && off=0
  printf '%s\n' "$size" > "$offset_file"
  tail -c "+$((off + 1))" -- "$f" 2> /dev/null |
    grep -cE "${CLUSTER_PEER_PROGRESS_PATTERN:-tokens-per-sec|Prompt:|Generation:}" || true
}

# One bounded generation, asked for directly. Success REQUIRES a token in the
# usage block: a 200 carrying an empty completion is the exact failure that let
# /v1/models look healthy for 900s, so HTTP status alone is not accepted.
probe_tokens() {
  [ -n "${CLUSTER_RANK_URL:-}" ] || return 1
  curl -fsS -m "${CLUSTER_PEER_PROBE_TIMEOUT_SECS:-120}" \
    -X POST "${CLUSTER_RANK_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${CLUSTER_MODEL:-}\",\"messages\":[{\"role\":\"user\",\"content\":\"liveness\"}],\"max_tokens\":1,\"stream\":false,\"temperature\":0}" \
    2> /dev/null | grep -qE '"completion_tokens"[[:space:]]*:[[:space:]]*[1-9]'
}

log_tail() {
  local -a logs
  read -ra logs <<< "${CLUSTER_RANK_LOGS:-}" || true
  [ "${#logs[@]}" -gt 0 ] || return 0
  tail -n "${CLUSTER_PEER_LOG_TAIL_LINES:-40}" -- "${logs[@]}" 2> /dev/null || true
}

# Headline the exception that killed the rank. Surfacing the REAL cause is most
# of the value here — the night this was built, the ValueError naming the wrong
# sharding mode sat in the worker's log the entire time and nothing read it.
rank_fault_line() {
  local -a logs
  read -ra logs <<< "${CLUSTER_RANK_LOGS:-}" || true
  [ "${#logs[@]}" -gt 0 ] || return 0
  grep -hoE '^[A-Za-z_][A-Za-z0-9_.]*(Error|Exception):.*' -- "${logs[@]}" 2> /dev/null |
    tail -n 1 || true
}
