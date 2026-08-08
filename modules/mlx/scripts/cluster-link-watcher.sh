# shellcheck shell=bash
# Cluster link watcher — one state-machine tick per launchd interval.
#
# Link state is a single ping to the peer's static link address (the route
# only exists while the Thunderbolt cable is in), converging the cluster
# rank to match:
#   link up, rank down : wired ceiling + quiesce, then (re)start the rank
#   link up, rank up   : coordinator readiness probe until :PORT answers once,
#                        then one untimed warm generation before traffic flips
#   link up -> down    : stop the rank, restore ceiling + normal serving
#
# Consumed environment (set declaratively by the launchd agent):
#   CLUSTER_ROLE            coordinator | worker
#   CLUSTER_STATIC_PEER_IP  peer's static link address
#   CLUSTER_STATIC_SELF_IP  this host's static link address (must be present on a
#                         carrier-active Thunderbolt port before a rank starts)
#   CLUSTER_RENDEZVOUS_PORT  JACCL rendezvous port — the worker confirms rank 0
#                         is listening there before spending a start attempt
#   CLUSTER_PEER_PROBE_TIMEOUT_SECS  bound on that TCP connect probe
#   CLUSTER_LINK_REPAIR     1 = repair a missing local link address in place
#   CLUSTER_LINK_ACTIVATE_TIMEOUT_SECS  bound on the activation repair fallback
#   CLUSTER_RANK_LABEL      launchd label of the cluster rank agent
#   CLUSTER_WARMUP_LABEL    launchd label of the normal-serving warmup one-shot
#   CLUSTER_NORMAL_PROXY    normal-mode llama-swap base URL (coordinator only)
#   CLUSTER_RANK_URL        cluster rank OpenAI base URL (coordinator only) —
#                         warmed once per link session after readiness
#   CLUSTER_MODEL           cluster model id sent in the warm generation request
#   CLUSTER_STATE_FILE      where the last observed link state is kept
#   CLUSTER_QUIESCE_CMD     optional worker-side quiesce hook (run via sh -c)
#   CLUSTER_RESTORE_CMD     optional worker-side restore hook (run via sh -c)
#   CLUSTER_MAX_KICKSTARTS  consecutive failed rank starts before halting
#   CLUSTER_PD_AUTO_REBOOT_WINDOW_SECS  minimum seconds between unattended
#                         reboots issued to clear a PD-exhaustion halt (0
#                         disables auto-reboot; see cluster-link-guards.sh
#                         pd_auto_reboot_if_warranted)
#   CLUSTER_LINK_DOWN_STRIKES  consecutive failed link probes before the link
#                         is declared down (default 2). Debounce only applies
#                         to down; up is believed on the first reply.
#   CLUSTER_ALERT_URL_FILE  local file holding a Slack incoming-webhook URL for
#                         the halt alert (untracked — never commit the URL)
#   CLUSTER_HTTP_PORT       coordinator only: cluster endpoint to readiness-probe
#   CLUSTER_LOAD_GRACE_SECS readiness grace for the model load (default 1800)
#   CLUSTER_WIRED_LIMIT_MB  optional: iogpu ceiling to hold while clustered
#                         (applied via the exact-value sudoers grant from
#                         nix-darwin; a failed apply SKIPS the rank start)
#   CLUSTER_STANDALONE_WIRED_LIMIT_MB  restore value at link-down (default 0)
#   CLUSTER_SERVER_LABEL    coordinator only: normal-mode server (llama-swap)
#                         launchd label, bootstrapped before the warmup fires
#   CLUSTER_SERVER_PLIST    coordinator only: that agent's plist, for bootstrap
#   CLUSTER_MAX_WARM_FAILURES  consecutive post-readiness health-gate
#                         failures before the rank is declared wedged
#   CLUSTER_WARM_RECHECK_SECS  soak interval: re-probe liveness this often once
#                         the gate has passed (default 600 = 10 min; 0 disables
#                         the soak)
#   CLUSTER_HEALTH_GATE_TIMEOUT_SECS  bound on one 1-token completion (default
#                         120), used by the gate's probe (b) and every soak
#                         recheck
#   CLUSTER_HEALTH_GATE_CONCURRENCY  N concurrent completions for the gate's
#                         probe (c) (default 2)
#   CLUSTER_HEALTH_GATE_CONCURRENT_TIMEOUT_SECS  bound on EACH of those N
#                         (default 180)
#   CLUSTER_SHARD_MEMORY_MB  expected per-rank working set in MB; 0 disables
#                         the memory-headroom rung with no vm_stat read at all
#                         (see mem_headroom_ok in cluster-link-guards.sh)
#   CLUSTER_MEM_HEADROOM_DWELL_TICKS  consecutive refused ticks before the
#                         memory rung escalates to a HALT that
#                         pd_auto_reboot_if_warranted can act on

mkdir -p "$(dirname "$CLUSTER_STATE_FILE")"
prev="down"
[ -f "$CLUSTER_STATE_FILE" ] && prev="$(cat "$CLUSTER_STATE_FILE")"

uid="$(id -u)"
state_dir="$(dirname "$CLUSTER_STATE_FILE")"
kicks_file="$state_dir/rank-kickstarts"
halt_file="$state_dir/rank-halted"
started_file="$state_dir/rank-first-running"
ready_file="$state_dir/rank-ready"
warm_file="$state_dir/rank-warmed"
warm_fails_file="$state_dir/rank-warm-failures"
# PASS/FAIL + per-probe evidence for every health-gate run and soak recheck,
# appended forever (never truncated) — the audit trail vk1188 exists to leave
# behind. See cluster-health-gate.sh.
health_gate_file="$state_dir/health-gate"
down_strikes_file="$state_dir/link-down-strikes"
# Consecutive ticks the PEER's rendezvous session has been absent while this
# rank is running and settled. Drives the pair-wide standdown below.
peer_session_strikes_file="$state_dir/peer-session-strikes"
# Consecutive launched attempts that died before the watcher ever observed them
# running, with no rendezvous session. Drives fast_fail_standdown — the same
# verdict as the counter above, for the rank that never lives long enough to
# reach it. Session-scoped like every other strike counter here.
fast_fail_strikes_file="$state_dir/rank-fast-fails"
# Consecutive ticks the probe has failed while the link was ALREADY down. Used
# only to make a permanently-failing probe audible on a cadence — see the
# else-branch of the probe below.
down_quiet_file="$state_dir/link-down-quiet-ticks"
# Last DOWN facts line actually logged, so a state CHANGE is reported the tick it
# happens instead of waiting out the quiet cadence. 10,440 identical lines is not
# reporting; it is the thing that hides the one line that mattered.
facts_file="$state_dir/link-facts-last"
# Consecutive failed link-prep self-heal attempts. Reset the moment prep is
# healthy, so a repair that works costs one attempt and one that cannot work
# stops instead of thrashing bridge0 membership every 30s for days.
link_prep_repairs_file="$state_dir/link-prep-repairs"
# Generation-parity cache (`<epoch> <fact>`), TTL CLUSTER_GENERATION_CHECK_SECS,
# and the marker that keeps a drift page to one per distinct drift.
gen_parity_file="$state_dir/generation-parity"
gen_alerted_file="$state_dir/generation-alerted"
# Sticky companion to halt_file: survives a manual `rm` of the marker so the
# next tick can re-verify the cause before the first retry (see
# halt_clear_accepted). Cleared only by a real link cycle or an accepted clear.
halt_latch_file="$state_dir/rank-halt-latched"
# Ledger of RDMA protection domains this boot has already leaked. Path comes from
# the module (single definition) — deliberately NOT derived here, because
# cluster-detach writes it and this agent reads it, and two derivations of one
# path is how a writer and a reader end up on different files. Deliberately NOT
# in the marker list either: a link cycle, a manual clear and cluster-join all
# reset the halt state, and none of them returns a protection domain.
pd_debt_file="${CLUSTER_PD_DEBT_FILE:-}"
# RULE 1 — plugged in means clustered. The lease is the ONE sanctioned,
# self-expiring standalone window (written by cluster-detach, deleted by
# cluster-join or its own expiry); the re-up counter bounds the port
# re-admin-up that makes a detached-while-plugged state self-correcting.
lease_file="$state_dir/standalone-lease"
port_reup_file="$state_dir/port-reups"
# RULE 2 — the detached generation-heal's attempts ledger (`<rev> <count>`).
heal_attempts_file="$state_dir/generation-heal-attempts"
# Wall-clock rate-limit marker for the PD-exhaustion auto-reboot (see
# pd_auto_reboot_if_warranted in cluster-link-guards.sh). Lives in state_dir
# like every OTHER marker here — unlike pd_debt_file, this one is watcher-only
# (cluster-join and cluster-detach never read or write it), so it does not need
# the module-derived single-definition treatment the ledger path gets.
pd_auto_reboot_marker_file="$state_dir/pd-auto-reboot-last"
# Consecutive ticks the memory-headroom rung has refused a start. Session-
# scoped like the other strike counters above (down_strikes_file, peer_
# session_strikes_file) — a shortfall is not a leaked kernel resource, so a
# link cycle resetting it is correct rather than laundering anything.
mem_dwell_file="$state_dir/mem-headroom-refused"

# GENERATION PARITY FIRST — RULE 2. Read (cached, one ls-remote per
# CLUSTER_GENERATION_CHECK_SECS) before ANY other step of the tick, because
# every later step's behaviour depends on the generation: link prep aliases
# what the deployed activation says, quiesce and rank start assemble the stack
# the deployed revision defines. Until 2026-08-01 the only parity check lived
# in cluster-join, which is human-initiated — so a drifted node stayed drifted
# for 86 hours. Now: reported every tick, paged once per distinct drift, and
# RECONCILED unattended by a detached launchd job (see
# cluster-generation-heal.sh — detached because a rebuild fired from this
# agent would be SIGKILLed by its own activation). While drift persists,
# rank_start_preconditions_ok refuses to start (hard gate) and the down path
# below refuses to run link prep from the stale generation.
parity_now="$(generation_parity_cached "$gen_parity_file")"
generation_drift_report "$parity_now" "$gen_alerted_file"
generation_heal_maybe "$parity_now" "$heal_attempts_file" || true

# Link probe, debounced ASYMMETRICALLY — a false "down" is destructive, a false
# "up" is not. Declaring down tears the rank down, restores standalone serving,
# and (crucially) the up->down handler deletes BOTH rank-kickstarts and
# rank-halted, which resets the RDMA PD guard. Declaring up merely tries a
# kickstart, which that same guard already caps. So "up" is believed on the
# first reply and "down" must be earned.
#
# Why this matters: every failed mx.distributed.init() leaks a kernel RDMA
# Protection Domain and exhaustion is reboot-only, so the guard halts after
# CLUSTER_MAX_KICKSTARTS consecutive failures. A flapping link defeats it
# entirely — each spurious down zeroes the counter, so the halt can never
# accumulate. Seen 2026-07-19: HALT fired once, then six up/down cycles each
# logging "kickstarting (attempt 1)" and never reaching 2, with 135
# `fork: Resource temporarily unavailable` errors as the quiesce/restore churn
# ran every 30s.
#
# Two layers, both cheap:
#   1. -c 3 instead of -c 1: any one reply is enough, so a single dropped
#      packet no longer reads as a pulled cable. Costs ~2s only when the peer
#      is genuinely gone, on a 30s tick.
#   2. Consecutive-tick confirmation: a failed probe while the link was up
#      is a strike, not a transition. Down is declared at
#      CLUSTER_LINK_DOWN_STRIKES (default 2), so a real unplug is seen within
#      ~1 extra tick while a multi-second transient is absorbed.
if /sbin/ping -c 3 -t 2 -q "$CLUSTER_STATIC_PEER_IP" > /dev/null 2>&1; then
  cur="up"
  rm -f "$down_strikes_file" "$down_quiet_file" "$facts_file"
elif [ "$prev" = "up" ]; then
  strikes=0
  [ -f "$down_strikes_file" ] && strikes="$(cat "$down_strikes_file")"
  strikes=$((strikes + 1))
  printf '%s\n' "$strikes" > "$down_strikes_file"
  if [ "$strikes" -ge "${CLUSTER_LINK_DOWN_STRIKES:-2}" ]; then
    cur="down"
    rm -f "$down_strikes_file"
  else
    # Hold the previous state: not a transition, so no teardown and no
    # PD-guard reset. Logged because a link that strikes repeatedly without
    # ever reaching the threshold is a failing cable, and that pattern is
    # invisible if the tick stays silent.
    echo "cluster-link: probe failed ($strikes/${CLUSTER_LINK_DOWN_STRIKES:-2}) — holding up"
    cur="up"
  fi
else
  # Link was ALREADY down and the probe still fails. This branch used to be
  # completely silent, which is how a permanently broken probe hid for 65
  # minutes on 2026-07-25: the agent ticked 115 times, exited 0 every time,
  # wrote nothing to stdout OR stderr, and `launchctl print` reported
  # `runs = 115, last exit code = 0`. Every health signal read green while the
  # cluster could not form.
  #
  # It then went the other way, and that was worse. The replacement logged a
  # two-item GUESS — "cable out, OR ... denied macOS Local Network permission" —
  # 10,440 times across 86 hours on 2026-08-01, while the truth was neither: the
  # cable was seated, a Thunderbolt port had carrier throughout, and this host
  # simply held no link address because it had drifted off the deployed
  # generation and the activation that aliases the address never ran. Any
  # enumerated cause list is non-exhaustive; offering two makes a reader pick one
  # and diagnose the wrong machine.
  #
  # So: REPAIR FIRST, then report MEASURED STATE. link_prep_self_heal fixes
  # exactly the condition that caused the outage — carrier present, address
  # absent — with the same repair the up-path already used, bounded so it cannot
  # thrash. link_facts then renders per-port carrier, where the self address
  # actually is, whether prep is usable, whether the peer answered and whether
  # this node is running the deployed generation, with no inference beyond one
  # definitional statement. Reported when the facts CHANGE (so a state change is
  # never buried under a quiet window) and otherwise on the existing cadence.
  cur="down"
  downs=0
  [ -f "$down_quiet_file" ] && downs="$(cat "$down_quiet_file")"
  downs=$((downs + 1))
  printf '%s\n' "$downs" > "$down_quiet_file"
  # RULE 1 — PLUGGED IN MEANS CLUSTERED, NO EXCEPTIONS. A detached-while-plugged
  # state must be self-correcting, never stable. The one sanctioned exception is
  # an unexpired standalone lease (deliberate, recorded, self-expiring); while
  # it holds, the watcher leaves the machine alone. Otherwise it first
  # re-admin-ups any port cluster-detach downed — carrier is unobservable on an
  # admin-down port, which is exactly why this state used to be stable — and
  # then repairs link prep, EXCEPT while the generation has drifted (RULE 2:
  # link prep from a stale generation applies stale config; the detached heal's
  # own activation re-runs prep from the deploy revision instead). A genuinely
  # absent carrier changes nothing here: re-up no-ops on admin-up ports and the
  # self-heal is carrier-gated, so a real unplug stays quiet.
  if standalone_lease_active "$lease_file"; then
    :
  else
    tb_ports_readmin_up "$port_reup_file" || true
    case "$parity_now" in
      *'state=drift'*) : ;;
      *) link_prep_self_heal "$link_prep_repairs_file" || true ;;
    esac
  fi
  facts="$(link_facts no "$gen_parity_file" "$lease_file")"
  last_facts=""
  [ -f "$facts_file" ] && last_facts="$(cat "$facts_file")"
  if [ "$facts" != "$last_facts" ] \
    || [ "$((downs % ${CLUSTER_DOWN_REPORT_EVERY:-20}))" -eq 0 ]; then
    printf '%s\n' "$facts" > "$facts_file"
    echo "cluster-link: DOWN $downs consecutive tick(s) — $facts"
  fi
fi

if [ "$cur" = "up" ]; then
  if [ "$prev" = "down" ]; then
    echo "cluster-link: down -> up ($CLUSTER_ROLE)"
  fi
  # Converge every tick while the link is up: restart a crashed rank — but
  # CAP the retries. Every failed `mx.distributed.init()` leaks a kernel
  # RDMA Protection Domain and exhaustion is reboot-only (ml-explore/mlx
  # #3207, exo-explore/exo#1847), so an unbounded crash loop turns one bad
  # start into a forced reboot. After the cap: halt and page once.
  if launchctl print "gui/$uid/$CLUSTER_RANK_LABEL" 2>/dev/null | grep -q "state = running"; then
    if [ ! -f "$started_file" ]; then
      touch "$started_file"
    fi
    # OBSERVATION ONLY — no branch below depends on this.
    #
    # launchd owns the JOB, not necessarily the engine. The two disagree in both
    # directions and each direction matters: during the ~20-30s a rank spends
    # resolving dependencies the job is running before any engine exists, and a
    # re-parented engine keeps its protection domain long after the job is gone.
    # Logging the disagreement makes the second case visible as it develops,
    # instead of only when the start guard later refuses to start over the
    # survivor. Deliberately inert: a wrong pattern must never be able to tear
    # down a healthy rank, so it may inform an operator and nothing else.
    if ! rank_process_running; then
      echo "cluster-link: NOTE launchd reports $CLUSTER_RANK_LABEL running but no engine process matches '${CLUSTER_RANK_PROCESS_PATTERN:-unset}' (normal briefly at start; persistent = the pattern or the launcher changed)"
    fi
    # `state = running` is NOT evidence the rank started. mlx_lm.server reaches
    # it immediately and then sits in the jaccl connect back-off (2s+4s+8s)
    # before mx.distributed.init() throws errno 60 and exits. A tick landing
    # inside that window used to clear the PD guard unconditionally — so the
    # halt was cleared by the corpse of the very attempt that tripped it, and
    # the watcher retried forever. Observed 2026-07-25: three complete
    # halt -> clear -> 3x kickstart cycles back to back, each leaking another
    # protection domain. PD exhaustion is reboot-only, so a defeated guard is
    # worse than none: it spends the budget while reporting it is protecting it.
    #
    # Require the process to have SETTLED before believing it.
    settled_at="$(/usr/bin/stat -f %m "$started_file" 2> /dev/null || echo 0)"
    if [ "$settled_at" -gt 0 ] &&
      [ "$(($(date +%s) - settled_at))" -ge "${CLUSTER_RANK_SETTLE_SECS:-60}" ]; then
      # A settled rank vindicates exactly ONE attempt — the last one, which is
      # the rank now running and holding its domain live. Every earlier attempt
      # in this counter was superseded by another kickstart, so it failed, and a
      # failed distributed init leaks a domain whether or not a later one
      # succeeded. Deleting the counter here (as this line used to) wrote those
      # losses off, which is how a boot could reach exhaustion with the ledger
      # still reading empty.
      pd_debt_settle_counter "$pd_debt_file" "$kicks_file" 1 "rank-settled" \
        "attempts that failed before the rank that settled"
      rm -f "$halt_file" "$halt_latch_file"
    fi
    # PAIR-WIDE STANDDOWN. A jaccl group cannot re-admit a rank, so a rank whose
    # peer has gone can never generate again — yet nothing here noticed. Measured
    # 2026-07-26: killing the worker left the coordinator's process alive and
    # answering /v1/models while every request hung to timeout with zero bytes,
    # and the restarted worker could not rejoin (errno 60). Separately, a worker
    # that halts on its own leaves the coordinator waiting in distributed init
    # until the ~1800s load grace expires, then restarting into the same wait.
    # Both are the same defect: one rank holding state its peer abandoned.
    #
    # Absence of the rendezvous session is now an accepted trigger — its
    # persistence across a full generation is MEASURED (see
    # peer_rendezvous_session in cluster-link-helpers.sh), which is what the old
    # classification-only gate was waiting for. Strikes, not one tick, because a
    # single missed sample must not tear down a healthy pair.
    if [ -f "$started_file" ]; then
      settle="$(/usr/bin/stat -f %m "$started_file" 2> /dev/null || echo 0)"
      if [ "$settle" -gt 0 ] &&
        [ "$(($(date +%s) - settle))" -ge "${CLUSTER_RANK_SETTLE_SECS:-60}" ]; then
        if peer_rendezvous_session; then
          rm -f "$peer_session_strikes_file"
        else
          # Same read idiom as the link-down strikes above; read_int lives in
          # cluster-peer-observe.sh, which the watcher does not concatenate.
          strikes=0
          [ -f "$peer_session_strikes_file" ] && strikes="$(cat "$peer_session_strikes_file")"
          strikes=$((strikes + 1))
          printf '%s\n' "$strikes" > "$peer_session_strikes_file"
          echo "cluster-link: peer rendezvous session ABSENT ($strikes/${CLUSTER_PEER_SESSION_STRIKES:-3})"
          if [ "$strikes" -ge "${CLUSTER_PEER_SESSION_STRIKES:-3}" ]; then
            echo "cluster-link: peer rank is gone; standing this rank down so the pair re-arms together (a jaccl group cannot re-admit a rank)"
            # Halt FIRST, exactly as the warm-wedged teardown below does. Without
            # it this teardown deletes its own strike counter two lines down and
            # writes no suppression, so the next tick kickstarts the rank, it
            # settles, the peer is still absent, strikes re-accumulate, and this
            # block fires again — forever. Measured on jevans-ms with the
            # Thunderbolt cable out: 560 standdowns and 1686 rendezvous-absent
            # strikes between 2026-07-12 and 2026-08-05. Each pass calls
            # restore_normal_serving below, which kickstarts the warmup agent and
            # holds llama-swap's single concurrency slot for the length of the
            # warm, so the loop starves normal serving (mlx-warmup.py names this
            # path as the uncapped caller in its RE-INVOCATION BOUND note).
            #
            # No new knob is needed: halt_drop_if_pre_boot clears this on the
            # next boot and a real link cycle clears the latch, so replugging the
            # cable still recovers on its own.
            halt_write "$halt_file" "$halt_latch_file" "peer-absent" \
              "$strikes consecutive rendezvous-absent strikes; peer rank unreachable"
            launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
            rm -f "$started_file" "$ready_file" "$warm_file" "$peer_session_strikes_file"
            if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
              set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
            fi
            restore_normal_serving || true
            alert "$(hostname -s): peer rank vanished; this rank was stood down and the host restored to standalone serving so both sides re-arm on the same start boundary. Replug the link to retry — the halt is deliberate and suppresses restarts until the link cycles." \
              "mlx-cluster pair-wide standdown"
          fi
        fi
      fi
    fi
    # Readiness probe (coordinator): launchctl "running" cannot see a rank
    # that hung inside distributed init or the model load. Until the endpoint
    # has answered once, a rank older than the load-grace window is declared
    # hung and restarted (the PD-guard kickstart cap above still applies).
    # ponytail: readiness-only — a once-ready rank is never probed again,
    # because mlx_lm.server blocks HTTP during long generations and a timed
    # probe would kill healthy ranks; post-ready health needs request-aware
    # metrics the server does not expose yet.
    if [ "$CLUSTER_ROLE" = "coordinator" ] && [ -n "${CLUSTER_HTTP_PORT:-}" ] && [ ! -f "$ready_file" ]; then
      if curl -fsS -m 5 "http://127.0.0.1:$CLUSTER_HTTP_PORT/v1/models" > /dev/null 2>&1; then
        touch "$ready_file"
        echo "cluster-link: rank ready (:$CLUSTER_HTTP_PORT answering)"
      else
        started_time=$(/usr/bin/stat -f %m "$started_file" 2> /dev/null || echo 0)
        if [ "$started_time" -gt 0 ]; then
          age=$(($(date +%s) - started_time))
          if [ "$age" -ge "${CLUSTER_LOAD_GRACE_SECS:-1800}" ]; then
            echo "cluster-link: rank running but not ready after ${age}s; restarting (hung init)"
            launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
            rm -f "$started_file"
          fi
        fi
      fi
    fi
    # SOAK: while the gate has already passed once this session (warm_file
    # present), re-probe liveness on an interval — vk1188. This is the same
    # re-arm timer the wedge detector used to drive (CLUSTER_WARM_RECHECK_SECS),
    # repurposed: instead of dropping the marker to make the block below redo
    # a single curl, it now calls the health gate's own soak probe directly and
    # appends the result to health_gate_file, so the evidence trail covers the
    # whole session, not just the first pass.
    #
    # Only probe (b) (one 1-token completion) — re-running the full N-way
    # concurrent probe every ~10 minutes would compete with real traffic for
    # the same proxy concurrency slot it exists to verify is healthy. A single
    # failure halts immediately (no consecutive-failure tolerance, unlike the
    # start guards above): this runs every ~10 minutes rather than every 30s
    # tick, so one miss here is already a sustained symptom, not a transient
    # one landing mid-generation.
    #
    # Case actually observed (2026-07-25): the one-token warm succeeded, then
    # the rank wedged on a real 8-token request — 0 bytes after 900s, both
    # ranks spinning at ~100% CPU. Readiness stayed latched and nothing
    # escalated for over an hour. This soak is what would have caught it.
    if [ "$CLUSTER_ROLE" = "coordinator" ] && [ -f "$warm_file" ] &&
      [ ! -f "$halt_file" ] && [ "${CLUSTER_WARM_RECHECK_SECS:-600}" -gt 0 ]; then
      warmed_at="$(/usr/bin/stat -f %m "$warm_file" 2> /dev/null || echo 0)"
      if [ "$warmed_at" -gt 0 ] &&
        [ "$(($(date +%s) - warmed_at))" -ge "${CLUSTER_WARM_RECHECK_SECS:-600}" ]; then
        echo "cluster-link: soak re-check (warm marker older than ${CLUSTER_WARM_RECHECK_SECS:-600}s)"
        if health_gate_soak_probe "$health_gate_file" "$CLUSTER_RANK_URL" "${CLUSTER_MODEL:-}" \
          "${CLUSTER_HEALTH_GATE_TIMEOUT_SECS:-120}"; then
          touch "$warm_file"
        else
          echo "cluster-link: soak probe FAILED (${HEALTH_GATE_DETAIL:-no detail}); declaring the rank WEDGED and restoring standalone serving" >&2
          halt_write "$halt_file" "$halt_latch_file" "health-gate-soak-fail" \
            "${HEALTH_GATE_DETAIL:-soak completion probe failed}"
          launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
          if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
            set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
          fi
          restore_normal_serving || true
          alert "$(hostname -s): cluster rank failed its periodic soak health-check (${HEALTH_GATE_DETAIL:-no detail}); torn down to standalone serving. Replug the link to retry." \
            "mlx-cluster rank wedged (soak)"
        fi
      fi
    fi

    # THE HEALTH GATE: once the rank is ready, run the full automated check —
    # vk1188, replacing the human who used to run this by hand every night.
    # (a) /v1/models answers, (b) one real completion inside a real timeout
    # with a non-empty body, (c) N of those AT ONCE (matching the proxy's own
    # concurrencyLimit), (d) the host is not already over its wired ceiling.
    # Coordinator-only (only rank 0 binds the endpoint) and idempotent per link
    # session via the rank-warmed marker, which link-down clears.
    if [ "$CLUSTER_ROLE" = "coordinator" ] && [ -f "$ready_file" ] && [ ! -f "$warm_file" ] &&
      [ ! -f "$halt_file" ] && [ -n "${CLUSTER_RANK_URL:-}" ]; then
      echo "cluster-link: rank ready; running the automated health gate"
      if health_gate_run "$health_gate_file" "$CLUSTER_RANK_URL" "${CLUSTER_MODEL:-}" \
        "${CLUSTER_HEALTH_GATE_TIMEOUT_SECS:-120}" "${CLUSTER_HEALTH_GATE_CONCURRENCY:-2}" \
        "${CLUSTER_HEALTH_GATE_CONCURRENT_TIMEOUT_SECS:-180}" "${CLUSTER_WIRED_LIMIT_MB:-0}"; then
        echo "cluster-link: health gate PASSED"
        touch "$warm_file"
        rm -f "$warm_fails_file"
      else
        # Readiness is a one-shot latch: /v1/models answering once is never
        # re-verified, so a rank that serves the probe but wedges on real
        # generation (INC-17070) would sit here retrying forever with nothing
        # escalating. Count consecutive post-readiness gate failures and tear
        # down to standalone at the cap instead of running wedged.
        warm_fails=0
        [ -f "$warm_fails_file" ] && warm_fails="$(cat "$warm_fails_file")"
        warm_fails=$((warm_fails + 1))
        printf '%s\n' "$warm_fails" > "$warm_fails_file"
        echo "cluster-link: health gate FAILED (${HEALTH_GATE_DETAIL:-no detail}), attempt $warm_fails/${CLUSTER_MAX_WARM_FAILURES:-3}" >&2
        if [ "$warm_fails" -ge "${CLUSTER_MAX_WARM_FAILURES:-3}" ]; then
          echo "cluster-link: health gate failed $warm_fails times after readiness; declaring the rank WEDGED and restoring standalone serving" >&2
          # Reuse the PD-guard halt latch: it already suppresses restarts until
          # the link cycles, so the wedged rank is not immediately restarted.
          halt_write "$halt_file" "$halt_latch_file" "health-gate-fail" \
            "$warm_fails consecutive post-readiness health-gate failures (${HEALTH_GATE_DETAIL:-no detail})"
          launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
          if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
            set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
          fi
          restore_normal_serving || true
          # Through alert(), never a raw curl: this page used to POST an
          # ntfy-style body with Priority/Title HEADERS, which the Slack webhook
          # rejects as invalid_payload — and `-fsS ... || true` then swallowed
          # both the rejection and the message. Silent by construction.
          alert "$(hostname -s): cluster rank answered /v1/models but failed $warm_fails consecutive health-gate checks (${HEALTH_GATE_DETAIL:-no detail}); torn down to standalone serving. Replug the link to retry." \
            "mlx-cluster rank wedged (health gate)"
        fi
      fi
    fi
  elif halt_drop_if_pre_boot "$halt_file" "$halt_latch_file" "$kicks_file" &&
    pd_debt_halt_if_exhausted "$halt_file" "$halt_latch_file" "$pd_debt_file" &&
    mem_headroom_halt_if_persistent "$halt_file" "$halt_latch_file" "$mem_dwell_file" &&
    [ -f "$halt_file" ]; then
    # Halted — no more PD-burning retries until the link cycles.
    #
    # Order matters and is the point: halt_drop_if_pre_boot first, so a reboot
    # really does clear a stale verdict, then the ledger re-halts if THIS boot
    # has already lost domains, and the memory rung re-halts if a shortfall is
    # still persisting. All three run every tick and always return 0, so
    # `[ -f "$halt_file" ]` is the actual gate.
    #
    # ...and a reboot is exactly what this next line can now issue itself: a
    # PD-exhaustion halt (pd-debt-exhausted or rank-start-failures) or a
    # persistent memory shortfall (insufficient-memory-persistent) is a
    # verdict whose own doctrine is "only a reboot clears this", so waiting on
    # a human to notice the alert is a manual interlock, not a design choice.
    # No-ops for every other halt cause, is its own rate limiter, and refuses
    # outright on a FileVault host with no credential to answer an unattended
    # authenticated restart — see pd_auto_reboot_if_warranted for all three.
    pd_auto_reboot_if_warranted "$halt_file" "$pd_auto_reboot_marker_file" "$cur"
  elif [ -f "$halt_latch_file" ] &&
    ! halt_clear_accepted "$halt_file" "$halt_latch_file" "$kicks_file"; then
    : # cleared by hand while the cause persists — re-halted, logged, no retry
  else
    kicks=0
    [ -f "$kicks_file" ] && kicks="$(cat "$kicks_file")"
    if [ "$kicks" -ge "${CLUSTER_MAX_KICKSTARTS:-3}" ]; then
      echo "cluster-link: rank failed $kicks consecutive starts; HALTING kickstarts (RDMA PD guard); restoring normal serving"
      halt_write "$halt_file" "$halt_latch_file" "rank-start-failures" \
        "$kicks consecutive failed rank starts"
      # THE LEAK IS NOW WRITTEN DOWN, not just halted on. Every one of those
      # $kicks failed distributed inits leaked a protection domain — that is the
      # entire reason this counter exists. Until now the loss lived only in the
      # counter, and the counter is SESSION-scoped: a link cycle, a settled rank
      # or a cluster-join resets it, so the next session started again from a
      # full budget of $kicks while the kernel had already lost that many
      # domains. Repeat a few times and the host reaches "reboot or nothing"
      # with every guard still reporting green. The ledger is boot-scoped, so
      # this debt now survives every one of those resets and only a reboot
      # settles it.
      # Recorded AND the counter zeroed, in one operation. Leaving the counter
      # at the cap after recording it meant the next path to reset it (an
      # accepted manual clear, a link cycle, cluster-join) would see a non-zero
      # count that had ALREADY been paid for — so the same attempts would be
      # billed to the ledger twice. The counter now holds only what is still
      # unrecorded, which is what makes every other reset site safe to settle.
      pd_debt_settle_counter "$pd_debt_file" "$kicks_file" 0 "rank-start-failures" \
        "$kicks consecutive failed distributed inits, one protection domain each"
      # Every attempt was preceded by quiesce_normal_serving, which boots the
      # standalone model server out. Halting without undoing that leaves the
      # host serving NOTHING for as long as the link stays up, because the only
      # restore was on the up->down edge — an edge that never comes when the
      # link is healthy and it is the PEER that cannot form the cluster.
      # Observed 2026-07-25: the worker served no inference for over an hour
      # while its own link probe read up. The warm-wedged path above already
      # does this; the PD-guard path simply forgot to.
      if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
        set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
      fi
      restore_normal_serving || true
      # Report the cost as a fraction of the device's own budget, not as a bare
      # count of failed starts: the operator needs to know how much of an
      # eleven-domain pool this just spent, not only that a counter hit its cap.
      alert "$(hostname -s): cluster rank failed $kicks consecutive starts; $(pd_debt_phrase "$(pd_debt_count "$pd_debt_file")" "${CLUSTER_MAX_KICKSTARTS:-?}"). Kickstarts halted and the host restored to standalone serving. errno 60 = reboot needed. Replug the link to reset, or clear the rank-halted marker — the watcher re-verifies the cause before retrying and will re-halt if it persists." \
        "mlx-cluster rank halted (PD guard)"
    elif fast_fail_standdown "$halt_file" "$halt_latch_file" \
      "$fast_fail_strikes_file" "$kicks" "$started_file"; then
      # Stood down: repeated starts died before settling and never reached
      # rendezvous. Ahead of the preconditions deliberately — the alignment hold
      # lives in there, and a peer that is not coming should cost no wait, the
      # same "no wait wasted" ordering rungs 1b and 1c already use.
      :
    elif ! rank_start_preconditions_ok; then
      # A precondition that is not yet met is NOT a failed start: nothing was
      # launched, so no protection domain leaked, so no attempt is consumed.
      # Retry next tick. The function logs which rung failed.
      :
    else
      # Quiesce BEFORE every (re)start, not only on the down->up edge: the
      # link-state file survives a reboot, so a host that boots with the
      # cable in arrives here as up->up with standalone serving warm — skipping the
      # quiesce there is how a rank shard and the standalone models end up wired
      # into the same 128 GB. Both hooks are idempotent, so a mid-run rank
      # restart re-running them is a no-op.
      quiesce_normal_serving
      echo "cluster-link: rank not running; kickstarting (attempt $((kicks + 1)))"
      rm -f "$started_file" "$ready_file" "$warm_file" "$warm_fails_file"
      launchctl kickstart "gui/$uid/$CLUSTER_RANK_LABEL" || true
      printf '%s\n' "$((kicks + 1))" > "$kicks_file"
    fi
  fi
elif [ "$prev" = "up" ]; then
  # THE UNPLUG PATH. Reached only after the link has failed
  # CLUSTER_LINK_DOWN_STRIKES consecutive probes, i.e. after the configured
  # settle window (clusterMode.linkDownSettleSecs, converted to strikes against
  # the watcher's own tick interval so the two numbers cannot drift apart) —
  # never on the first missed probe. Everything below is idempotent, and the
  # link-state edge is only consumed if it all succeeds, so a partial teardown
  # is retried rather than lost.
  echo "cluster-link: up -> down ($CLUSTER_ROLE) after ${CLUSTER_LINK_DOWN_STRIKES:-2} failed probes; tearing down and restoring normal serving"
  # A link cycle (replug) clears the PD-guard + readiness state and the warm
  # marker so the next link session re-warms its freshly started rank. This is
  # the ONE legitimate reset of the halt latch: the cable really did move, so
  # the cause the halt recorded is no longer assumed to hold.
  # The cable really did move, so the halt's recorded cause is no longer assumed
  # to hold — but the DOMAINS those attempts leaked did not come back with it.
  # Only a reboot returns one. So the counter is transferred to the boot-scoped
  # ledger before the link cycle clears it; unplugging and replugging must not
  # be a way to launder protection-domain debt out of the accounting, which is
  # exactly what deleting the counter here used to make it.
  pd_debt_settle_counter "$pd_debt_file" "$kicks_file" 0 "link-cycle" \
    "attempts outstanding when the link went down and reset the session"
  rm -f "$halt_file" "$halt_latch_file" "$started_file" "$ready_file" \
    "$warm_file" "$warm_fails_file" "$mem_dwell_file" "$fast_fail_strikes_file"
  launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
  if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
    set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || down_failed=1
  fi
  restore_normal_serving || down_failed=1
fi

# Consume the link-state edge only when the teardown actually completed. The
# down path is idempotent (marker rm -f, SIGTERM on a dead rank, an idempotent
# ceiling write, a bootstrap guarded on not-loaded, and a cluster-restore that
# deliberately keeps failed labels for retry), so leaving the state at "up"
# re-runs it next tick instead of losing the transition to a swallowed error.
if [ "${down_failed:-0}" -ne 0 ]; then
  echo "cluster-link: WARN teardown incomplete; holding link state 'up' so the next tick retries" >&2
else
  printf '%s\n' "$cur" > "$CLUSTER_STATE_FILE"
fi
