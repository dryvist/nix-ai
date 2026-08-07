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
#   CLUSTER_STANDALONE_PROBE_URL       normal-mode proxy /v1 base URL
#   CLUSTER_STANDALONE_PROBE_MODEL     primary resident model id (real-completion probe)
#   coordinator only:
#   CLUSTER_SERVER_LABEL        normal-mode server (llama-swap) launchd label
#   CLUSTER_SERVER_PLIST        path to the server agent plist (for bootstrap)
#   CLUSTER_WARMUP_LABEL        normal-mode warmup one-shot launchd label
#   worker only:
#   CLUSTER_RESTORE_CMD         cluster-restore — bootstraps back exactly the
#                             agents cluster-quiesce recorded booting out
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

# --- step 0: record the standalone lease (RULE 1: plugged in means clustered) --
# A detach is a bounded EXCEPTION, never a state. Twice on 2026-08-01 machines
# sat detached with the cable in — serving nothing clustered and running no
# benchmark — because nothing recorded that the standalone window was over. So
# every detach now writes a lease: `<expiry-epoch>\t<created>\t<reason>`, one
# line. The watcher honours it while it is unexpired and resumes driving the
# pair back to clustered the moment it expires; cluster-join ends it early.
# There is deliberately NO indefinite form — an opt-out that cannot expire
# recreates the exact failure the rule targets.
#
# Usage: cluster-detach [lease-secs [reason]]
lease_secs="${1:-${CLUSTER_STANDALONE_LEASE_SECS:-7200}}"
case "$lease_secs" in
  '' | *[!0-9]*)
    echo "cluster-detach: FAIL: lease duration '$lease_secs' is not a number of seconds (usage: cluster-detach [lease-secs [reason]])" >&2
    exit 1
    ;;
esac
lease_reason="${2:-cluster-detach}"
lease_until=$(($(date +%s) + lease_secs))
mkdir -p "$state_dir"
printf '%s\t%s\t%s\n' "$lease_until" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$lease_reason" \
  > "$state_dir/standalone-lease"
echo "cluster-detach: standalone lease for ${lease_secs}s (reason: $lease_reason). While the cable is in, the watcher auto-rejoins when it expires; cluster-join ends it early."

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

# SETTLE AFTER THE RANK IS ACTUALLY GONE, BEFORE JUDGING THE OTHER TWO ROWS.
# Only the rank's exit is this script's to force. Clearing the markers and
# restoring the standalone ceiling belong to the watcher's up->down teardown,
# which cannot start until the rank is gone -- so both the wait above (which
# ends the moment its combined condition holds) and every escalation branch
# below it can leave those two rows read while that teardown has not begun.
#
# That is a FALSE failure, and it looks exactly like a real one: on 2026-08-06
# detach exited 1 reporting markers present and the ceiling not reverted, and
# an UNCHANGED re-run converged, because the second invocation read the state
# the first one had already set in motion. A teardown that needs to be run
# twice to report the truth trains the operator to ignore its exit code.
#
# Bounded by the same CLUSTER_DETACH_TIMEOUT_SECS that bounds the wait above,
# and it breaks the instant both hold, so the ordinary unplug pays nothing.
if rank_gone; then
  settle_deadline=$(($(date +%s) + timeout))
  while [ "$(date +%s)" -lt "$settle_deadline" ]; do
    if markers_clear && ceiling_restored; then
      break
    fi
    sleep 5
  done
fi

markers_clear || note_fail "PD-guard/readiness markers still present in $state_dir"
rank_gone || note_fail "rank process still running (pattern ${CLUSTER_RANK_PROCESS_PATTERN:-unset})"
ceiling_restored ||
  note_fail "iogpu.wired_limit_mb=$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null) != standalone ${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}"
# Deliberately NOT called "teardown verified" any more. That wording was true and
# read as false: on 2026-08-01 it printed on a worker that was serving NOTHING,
# and exit 0 said the node was fine. Naming exactly the three postconditions it
# covers — and nothing about serving — is what stops the next reader making the
# same jump.
[ "$failed" -eq 0 ] && echo "cluster-detach: rank teardown verified (markers clear, rank gone, standalone ceiling restored); serving NOT yet restored — step 2"

# --- step 2: BOTH ROLES -- put standalone serving back and prove it serves ---
# THE 86-HOUR DEFECT. This step used to be coordinator-only. On a worker,
# cluster-detach downed the link, verified markers/rank/ceiling, printed
# "teardown verified" and exited 0 — while the seven agents cluster-quiesce had
# booted out (dev.mlx-model-server and its warmup among them) stayed booted out
# and the host answered connection-refused. The teardown really was verified. The
# machine really was serving nothing. Both at once, exit 0.
#
# Two changes make that unreachable:
#   1. restore_normal_serving is now the SHARED function the watcher and the
#      peer-liveness supervisor already call (scripts/cluster-serving-restore.sh),
#      so every path that claims to restore serving runs the same code. On a
#      worker it invokes cluster-restore, which bootstraps back EXACTLY the set
#      cluster-quiesce recorded — never a hardcoded list.
#   2. The real-completion probe runs for BOTH roles. A restore that cannot be
#      demonstrated with a generated token is not a restore.
if ! restore_normal_serving; then
  note_fail "standalone serving restore failed (role=$CLUSTER_ROLE)"
fi

serve_ok=false
if [ -n "${CLUSTER_STANDALONE_PROBE_URL:-}" ]; then
  echo "cluster-detach: waiting up to ${timeout}s for standalone serving to answer a real completion"
  deadline=$(($(date +%s) + timeout))
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
else
  # No probe URL is a CONFIGURATION gap, not a pass. Reporting it as a failure is
  # the point: an unverifiable restore is exactly the state this whole step
  # exists to stop being reported as success.
  note_fail "no CLUSTER_STANDALONE_PROBE_URL configured; standalone serving CANNOT be verified on this node"
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
if [ "$serve_ok" = true ]; then standalone_state="restored"; else standalone_state="NOT-RESTORED"; fi
echo "  standalone serving: $standalone_state"
echo "  lease      : ${lease_secs}s ($lease_reason) — the watcher auto-rejoins at expiry while plugged in"
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
