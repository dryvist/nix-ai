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
# Exit codes: 0 = OK; 3 = OK but reboot REQUIRED before the next join (stale
# swap, or the rank had to be SIGKILL'd — which leaks its RDMA protection domain
# as well as its wired shard memory, and is recorded as PD debt); 1 = a
# postcondition failed.

uid="$(id -u)"
state_dir="$(dirname "$CLUSTER_STATE_FILE")"
timeout="${CLUSTER_DETACH_TIMEOUT_SECS:-300}"
failed=0

note_fail() {
  echo "cluster-detach: FAIL: $*" >&2
  failed=1
}

# --- step 1: take the link admin-down ---------------------------------------
# iface_holding_self_ip comes from scripts/cluster-link-locate.sh, concatenated
# ahead of this body by cluster-cli-builder.nix and shared with cluster-join and
# the link watcher.
port="$(iface_holding_self_ip)"
if [ -n "$port" ] && [ "$port" != "bridge0" ]; then
  echo "cluster-detach: taking $port ($CLUSTER_STATIC_SELF_IP) admin-down"
  sudo -n /sbin/ifconfig "$port" down > /dev/null 2>&1 ||
    note_fail "could not down $port (ifconfig en[0-9]* down grant missing?)"
else
  echo "cluster-detach: no port holds $CLUSTER_STATIC_SELF_IP (link already down?)"
fi

# --- wait for the watcher's up->down teardown, verified against live state ---
# The up->down edge clears these markers, stops the rank, and restores the
# standalone ceiling. Poll until ALL hold (or time out) -- never trust the log.
# rank-halt-latched is included because a leftover latch makes the NEXT session's
# first rank start re-verify (and possibly re-halt) instead of simply starting:
# "safe to rejoin" has to mean the halt state is gone, not just the halt marker.
markers=(
  rank-halted rank-halt-latched rank-kickstarts
  rank-first-running rank-ready rank-warmed
)

markers_clear() {
  local m
  for m in "${markers[@]}"; do
    [ -e "$state_dir/$m" ] && return 1
  done
  return 0
}
# rank_process_absent comes from scripts/cluster-rank-proc.sh and matches on
# CLUSTER_RANK_PROCESS_PATTERN — one definition (modules/mlx/cluster-rank-pattern.nix),
# derived from the same entry-point string that builds the rank argv. Two inline
# copies of '/mlx_lm\.server' used to live in this file.
#
# It is a POSITIVE proof of absence, not `! pgrep`: pgrep exits 1 for "no match"
# and 2/127 for "I could not answer", and collapsing those is how an unusable
# probe reports a node as safe to unplug while a rank still holds its RDMA
# protection domain.
rank_gone() { rank_process_absent; }
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

# GRACEFUL FIRST, AND AT THE PROCESS, NOT THE JOB. The SIGTERM above went to the
# launchd label; an engine that has been re-parented is no longer part of that
# job, so that signal reached nothing while the process kept its protection
# domain. rank_reap_verified signals the pids directly and then PROVES they are
# gone, using the same implementation the link watcher runs before every start —
# one definition, so the daily unplug and the unattended restart cannot drift
# into two different ideas of "the rank is gone".
if ! rank_gone; then
  rank_reap_verified "$timeout" || true
fi

# LAST RESORT, AND THE ONE AUDITED EXCEPTION. A rank still up here ignored
# SIGTERM twice (deep native/RDMA wedge). SIGKILL leaves the node serving-safe,
# but a SIGKILLed rank never runs its RDMA teardown, so it takes TWO things with
# it:
#
#   wired shard memory      — the loss this warning used to name
#   its protection domain   — the more expensive one, and the reason a reboot
#                             stops being "recommended" and becomes required
#
# So the kill is WRITTEN DOWN, in a boot-scoped ledger, before anything else
# happens. From that moment this host is one protection domain poorer for the
# rest of the boot, cluster-join refuses at the cap, and the link watcher halts
# rank starts BEFORE the kernel runs out instead of after errno 96 proves it did.
# An unaudited SIGKILL is exactly how the debt used to accumulate invisibly
# across sessions.
if ! rank_gone; then
  echo "cluster-detach: rank ignored SIGTERM; escalating to SIGKILL — this LEAKS its RDMA protection domain (reboot-only recovery) as well as its wired shard memory" >&2
  pd_debt_record "${CLUSTER_PD_DEBT_FILE:-}" 1 "detach-sigkill" \
    "rank $CLUSTER_RANK_LABEL ignored SIGTERM for ${timeout}s and was SIGKILLed"
  /bin/launchctl kill SIGKILL "gui/$uid/${CLUSTER_RANK_LABEL}" > /dev/null 2>&1 || true
  # NEVER pkill on an empty pattern: `pkill -f ''` matches every process on the
  # machine. An unset pattern is a configuration failure, not a licence to kill
  # the session.
  if [ -n "${CLUSTER_RANK_PROCESS_PATTERN:-}" ]; then
    /usr/bin/pkill -9 -f "$CLUSTER_RANK_PROCESS_PATTERN" > /dev/null 2>&1 || true
  else
    echo "cluster-detach: WARN CLUSTER_RANK_PROCESS_PATTERN unset; skipped the pattern-based kill (an empty pattern would match every process)" >&2
  fi
  sleep 3
  rank_gone && sigkilled_rank=1
fi

markers_clear || note_fail "PD-guard/readiness markers still present in $state_dir"
rank_gone || note_fail "rank process still running (pattern ${CLUSTER_RANK_PROCESS_PATTERN:-unset})"
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
# Three states, because "not proven gone" and "definitely still up" are
# different operator actions and collapsing them is how an unusable pgrep gets
# read as safe-to-unplug.
if rank_gone; then
  rank_state="stopped"
elif rank_process_running; then
  rank_state="RUNNING"
else
  rank_state="UNKNOWN (process probe could not answer)"
fi

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
# The number that decides whether this node may join again without a reboot.
# Reported unconditionally, including when it is 0/N: a debt line that only
# appears once there is debt is a line nobody learns to look for.
pd_debt_now="$(pd_debt_count "${CLUSTER_PD_DEBT_FILE:-}")"
echo "  PD debt    : $(pd_debt_phrase "${pd_debt_now:-0}" "${CLUSTER_PD_DEBT_MAX:-?}")"
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
  echo "cluster-detach: WARNING rank was SIGKILL'd -- it leaked its RDMA protection domain" >&2
  echo "                AND its wired shard memory. Recorded: $(pd_debt_phrase "${pd_debt_now:-?}" "${CLUSTER_PD_DEBT_MAX:-?}")" >&2
  echo "                in ${CLUSTER_PD_DEBT_FILE:-unset}. Reboot this node before the next join:" >&2
  echo "                a protection domain is returned by nothing else, and leaked wired" >&2
  echo "                memory is the INC-17076 panic risk. At the cap, cluster-join refuses" >&2
  echo "                and the link watcher halts rank starts on its own." >&2
  exit 3
fi
if [ "$stale_swap" = true ]; then
  echo "cluster-detach: WARNING stale swap -- reboot this node before the next join (or now):" >&2
  echo "                vm.swapusage used ${used}M > ${swap_threshold}M (INC-17075 spiral risk)" >&2
  exit 3
fi
exit 0
