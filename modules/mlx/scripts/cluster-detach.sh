# shellcheck shell=bash
# cluster-detach -- the daily safe-unplug front-end over the watcher teardown.
#
# Takes the Thunderbolt link admin-down so both watchers observe peer loss and
# run their up->down teardown (stop rank, clear markers, restore standalone ceiling and
# standalone serving), then VERIFIES each postcondition against live state rather than
# trusting the watcher logs. Ends the node in a state that is safe to unplug,
# sleep, or reboot, and ready to rejoin.
#
# Consumed environment (baked by the launchd/module wiring):
#   CLUSTER_ROLE                coordinator | worker
#   CLUSTER_STATIC_SELF_IP      this node's static link address (locates the port)
#   CLUSTER_STATE_FILE          watcher link-state file (locates the marker dir)
#   CLUSTER_WIRED_LIMIT_MB      optional: set => a standalone-ceiling restore is expected
#   CLUSTER_STANDALONE_WIRED_LIMIT_MB  standalone ceiling the watcher restores (default 0)
#   CLUSTER_DETACH_SWAP_THRESHOLD_MB  warn+exit-3 above this vm.swapusage used (MB)
#   CLUSTER_DETACH_TIMEOUT_SECS bound on the teardown/restore waits
#   coordinator only:
#   CLUSTER_SERVER_LABEL        normal-mode server (llama-swap) launchd label
#   CLUSTER_SERVER_PLIST        path to the server agent plist (for bootstrap)
#   CLUSTER_WARMUP_LABEL        normal-mode warmup one-shot launchd label
#   CLUSTER_STANDALONE_PROBE_URL       normal-mode proxy /v1 base URL
#   CLUSTER_STANDALONE_PROBE_MODEL     primary resident model id (real-completion probe)
#
# Grants used (nix-darwin sudoers, cluster-ops): `ifconfig en[0-9]* down` to drop
# the link. launchctl verbs run in the caller's own gui/$uid domain (no sudo).
#
# Exit codes: 0 = OK; 3 = OK but reboot recommended before the next join (stale
# swap, or the rank had to be SIGKILL'd and its wired shard memory likely
# leaked); 1 = a postcondition failed.

uid="$(id -u)"
state_dir="$(dirname "$CLUSTER_STATE_FILE")"
timeout="${CLUSTER_DETACH_TIMEOUT_SECS:-300}"
failed=0

note_fail() {
  echo "cluster-detach: FAIL: $*" >&2
  failed=1
}

# --- step 1: take the link admin-down ---------------------------------------
iface_holding_self_ip() {
  /sbin/ifconfig 2>/dev/null | /usr/bin/awk -v ip="$CLUSTER_STATIC_SELF_IP" '
    /^[a-z]/ { dev = $1; sub(/:$/, "", dev) }
    $1 == "inet" && $2 == ip { print dev; exit }
  '
}

port="$(iface_holding_self_ip)"
if [ -n "$port" ] && [ "$port" != "bridge0" ]; then
  echo "cluster-detach: taking $port ($CLUSTER_STATIC_SELF_IP) admin-down"
  sudo -n /sbin/ifconfig "$port" down > /dev/null 2>&1 ||
    note_fail "could not down $port (ifconfig en[0-9]* down grant missing?)"
else
  echo "cluster-detach: no port holds $CLUSTER_STATIC_SELF_IP (link already down?)"
fi

# --- wait for the watcher's up->down teardown, verified against live state ---
# The up->down edge clears these five markers, stops the rank, and restores the
# standalone ceiling. Poll until ALL hold (or time out) -- never trust the log.
markers=(rank-halted rank-kickstarts rank-first-running rank-ready rank-warmed)

markers_clear() {
  local m
  for m in "${markers[@]}"; do
    [ -e "$state_dir/$m" ] && return 1
  done
  return 0
}
rank_gone() { ! /usr/bin/pgrep -f 'mlx_lm.server' > /dev/null 2>&1; }
ceiling_restored() {
  [ -z "${CLUSTER_WIRED_LIMIT_MB:-}" ] && return 0
  [ "$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo '')" = "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" ]
}

# Stop the rank directly, not only via the watcher. The watcher's up->down
# teardown stops the rank, but on a DEADLOCKED rank the watcher can be stuck in
# its own blocking warm-generation curl and never reach the teardown, so the
# rank would survive the whole wait. A SIGTERM in our own gui/$uid domain lets
# MLX release its GPU buffers cleanly (a SIGKILL'd rank leaks its wired shard
# memory -- reboot-only recovery), so try SIGTERM first and escalate only if it
# does not land.
if ! rank_gone; then
  /bin/launchctl kill SIGTERM "gui/$uid/${CLUSTER_RANK_LABEL}" > /dev/null 2>&1 || true
fi

echo "cluster-detach: waiting up to ${timeout}s for the watcher teardown"
deadline=$(($(date +%s) + timeout))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if markers_clear && rank_gone && ceiling_restored; then
    break
  fi
  sleep 5
done

# Last resort: a rank still up here ignored SIGTERM (deep native/RDMA wedge).
# SIGKILL it so the node is at least serving-safe, but warn that its wired shard
# memory likely leaked and the node needs a reboot before the next join.
if ! rank_gone; then
  echo "cluster-detach: rank ignored SIGTERM; escalating to SIGKILL (wired shard memory may leak)" >&2
  /bin/launchctl kill SIGKILL "gui/$uid/${CLUSTER_RANK_LABEL}" > /dev/null 2>&1 || true
  /usr/bin/pkill -9 -f 'mlx_lm.server' > /dev/null 2>&1 || true
  sleep 3
  rank_gone && sigkilled_rank=1
fi

markers_clear || note_fail "PD-guard/readiness markers still present in $state_dir"
rank_gone || note_fail "mlx_lm.server rank process still running"
ceiling_restored ||
  note_fail "iogpu.wired_limit_mb=$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null) != standalone ${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}"
[ "$failed" -eq 0 ] && echo "cluster-detach: teardown verified (markers clear, rank gone, standalone ceiling restored)"

# --- step 2: coordinator -- verify standalone serving actually came back ------------
# The watcher restore assumes the standalone agents are still loaded and silently no-ops
# otherwise (INC-17071). Ensure the server agent is loaded, (re)kick it and the
# warmup, then require a REAL completion from the primary resident.
if [ "$CLUSTER_ROLE" = "coordinator" ]; then
  if ! /bin/launchctl print "gui/$uid/${CLUSTER_SERVER_LABEL}" > /dev/null 2>&1; then
    echo "cluster-detach: standalone server agent not loaded; bootstrapping"
    if [ -f "${CLUSTER_SERVER_PLIST:-}" ]; then
      /bin/launchctl bootstrap "gui/$uid" "$CLUSTER_SERVER_PLIST" > /dev/null 2>&1 || true
    fi
  fi
  /bin/launchctl kickstart "gui/$uid/${CLUSTER_SERVER_LABEL}" > /dev/null 2>&1 || true
  /bin/launchctl kickstart -k "gui/$uid/${CLUSTER_WARMUP_LABEL}" > /dev/null 2>&1 || true

  echo "cluster-detach: waiting up to ${timeout}s for standalone serving to answer a real completion"
  deadline=$(($(date +%s) + timeout))
  serve_ok=false
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if curl -fsS -m 5 "${CLUSTER_STANDALONE_PROBE_URL}/models" > /dev/null 2>&1; then
      body="$(curl -fsS -m 240 -X POST "${CLUSTER_STANDALONE_PROBE_URL}/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "$(jq -nc --arg m "${CLUSTER_STANDALONE_PROBE_MODEL:-}" \
          '{model:$m,messages:[{role:"user",content:"ping"}],max_tokens:4}')" \
        2> /dev/null)" || { sleep 10; continue; }
      if jq -e '(.usage.completion_tokens // 0) >= 1' > /dev/null 2>&1 <<< "$body"; then
        serve_ok=true
        break
      fi
    fi
    sleep 10
  done
  if "$serve_ok"; then
    echo "cluster-detach: standalone serving restored (real completion from $CLUSTER_STANDALONE_PROBE_MODEL)"
  else
    note_fail "standalone serving did not return a real completion within ${timeout}s"
  fi
fi

# --- step 3: swap check (distinct exit so a wrapper can chain a reboot) ------
swap_used_mb() {
  /usr/sbin/sysctl -n vm.swapusage 2>/dev/null | /usr/bin/sed -n 's/.*used = \([0-9][0-9]*\).*/\1/p'
}
used="$(swap_used_mb)"
used="${used:-0}"
swap_threshold="${CLUSTER_DETACH_SWAP_THRESHOLD_MB:-20000}"
stale_swap=false
[ "$used" -gt "$swap_threshold" ] && stale_swap=true

# --- step 4: state summary --------------------------------------------------
ceiling="$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo '?')"

if [ -n "$port" ]; then link_state="$port down"; else link_state="already down"; fi
if markers_clear; then markers_state="clear"; else markers_state="PRESENT"; fi
if rank_gone; then rank_state="stopped"; else rank_state="RUNNING"; fi

echo "======================================================================"
if [ "$failed" -eq 0 ]; then
  echo "cluster-detach OK ($CLUSTER_ROLE)"
else
  echo "cluster-detach FAIL ($CLUSTER_ROLE)"
fi
echo "  link       : $link_state"
echo "  markers    : $markers_state"
echo "  rank       : $rank_state"
echo "  wired ceil : iogpu.wired_limit_mb=$ceiling (standalone ${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0})"
if [ "$CLUSTER_ROLE" = "coordinator" ]; then
  if [ "$serve_ok" = true ]; then standalone_state="restored"; else standalone_state="NOT-RESTORED"; fi
  echo "  standalone serving: $standalone_state"
fi
echo "  swap used  : ${used}M (threshold ${swap_threshold}M)"
echo "======================================================================"

if [ "$failed" -ne 0 ]; then
  exit 1
fi
if [ "${sigkilled_rank:-0}" -eq 1 ]; then
  echo "cluster-detach: WARNING rank was SIGKILL'd -- its wired shard memory likely leaked;" >&2
  echo "                reboot this node before the next join (leaked wired -> INC-17076 panic risk)." >&2
  exit 3
fi
if [ "$stale_swap" = true ]; then
  echo "cluster-detach: WARNING stale swap -- reboot this node before the next join (or now):" >&2
  echo "                vm.swapusage used ${used}M > ${swap_threshold}M (INC-17075 spiral risk)" >&2
  exit 3
fi
exit 0
