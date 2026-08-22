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
#   CLUSTER_WATCHDOG_LABEL  coordinator only: serving watchdog launchd label,
#                         bootstrapped back by restore_normal_serving on every
#                         teardown this watcher owns (up->down edge, PD-guard
#                         halt, wedge teardown)
#   CLUSTER_WATCHDOG_PLIST  coordinator only: that agent's plist, for bootstrap
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
#   CLUSTER_RANK_PROGRESS_LOG  the rank's own log, tailed for real generation
#                         progress (new_progress_lines, cluster-peer-observe.sh)
#                         before the soak probe fires; empty skips the check
#   CLUSTER_PEER_PROGRESS_PATTERN  ERE marking token progress in that log
#   CLUSTER_STAT_BIN         stat path/seam for the soak marker's mtime read
#                         (BSD `-f %m` syntax); production absolute path,
#                         since the Linux Nix sandbox has no /usr/bin/stat
#   CLUSTER_SHARD_MEMORY_MB  expected per-rank working set in MB; 0 disables
#                         the memory-headroom rung with no vm_stat read at all
#                         (see mem_headroom_ok in cluster-link-guards.sh)
#   CLUSTER_MEM_HEADROOM_DWELL_TICKS  consecutive refused ticks before the
#                         memory rung escalates to a HALT that
#                         pd_auto_reboot_if_warranted can act on
#   CLUSTER_PEER_STATE_FILE  where this host publishes the JSON line its peer
#                         reads before starting a rank (cluster-peer-state.sh)
#   CLUSTER_PEER_STATE_PORT / _TIMEOUT_SECS / _STALE_SECS  the peer end of that
#                         channel: which port to read, how long to wait, and how
#                         old an answer may be before it is refused. Port 0
#                         disables the handshake entirely.
#   CLUSTER_PEER_HALT_STRIKES  consecutive peer-state reads reporting the peer
#                         halted, while this host's rank is settled, before this
#                         rank stands down too (worker-side; the coordinator's
#                         teardowns are endpoint-probing and cannot run here)
#   CLUSTER_PD_CAUSE_BUDGET domains one halt cause may spend across ALL boots
#                         before rank starts are refused (cluster-pd-cause.sh)
#   CLUSTER_HEARTBEAT_EVERY  ticks between the nominal-tick heartbeat line, so
#                         a watcher that is alive and one that stopped being
#                         scheduled do not log the same thing (0 disables)

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
# Byte size of CLUSTER_RANK_ERROR_LOG captured right before EACH kickstart, so
# fast_fail_standdown's stage classifier reads only what THIS attempt appended
# — StandardErrorPath accumulates across every rank restart, so a bare tail
# would otherwise still be reading the PREVIOUS attempt's evidence on a death
# that left no stderr of its own. See rank_failure_stage in
# ./cluster-pd-stage.sh.
rank_log_offset_file="$state_dir/rank-error-log-offset"
# Byte size of CLUSTER_RANK_ERROR_LOG captured ONCE, at the FIRST kickstart of
# an outstanding run — unlike rank_log_offset_file above, never overwritten by
# a later kickstart in the same run. pd_debt_settle_counter bills the whole
# run's outstanding attempts at once (kicks - vindicated), so classifying it
# needs the window from the run's START, not just its latest attempt: an
# earlier attempt in the same run could have reached Stage B and leaked a real
# domain while a later one only hit Stage A, and reading just the latest
# attempt's tail would misclassify the whole run as free on that later
# attempt's evidence alone — the exact staleness bug rank_log_offset_file
# exists to prevent, one level up. Settled (and cleared) alongside kicks_file
# by pd_debt_settle_counter itself.
session_log_offset_file="$state_dir/rank-error-log-session-offset"
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
# Last peer state this host acted on while halted, so an auto re-arm fires once
# per observed peer transition instead of once per tick. Deleted whenever no
# halt stands, which is what makes "no record" a transition in its own right —
# see peer_rearm_maybe in cluster-peer-state.sh for why that case is the one
# that actually strands a pair.
peer_seen_file="$state_dir/peer-state-last"
# Consecutive peer-state reads in which the PEER reported a halt while this
# host's own rank was settled. Drives the worker-side standdown below; session-
# scoped like every other strike counter here, and cleared by the first clean
# read. Its companion file's mtime is the standdown check's own cadence clock —
# a worker never has the coordinator's warm marker to time itself against,
# because the health gate that writes it is coordinator-only.
peer_halt_strikes_file="$state_dir/peer-halt-strikes"
peer_halt_check_file="$state_dir/peer-halt-last-check"
# Ticks since this marker was created, for the nominal-tick heartbeat below.
# Never reset by anything: it is a liveness odometer, not a strike counter, and
# a counter that resets on a state change is one whose gaps cannot be read.
heartbeat_file="$state_dir/heartbeat-ticks"
# Consecutive soak ticks deferred because a request was in flight. Session-
# scoped like every other strike counter here — see the soak block for why a
# busy pipeline must not be probed, and why the deferral is nonetheless bounded.
soak_busy_skips_file="$state_dir/soak-busy-skips"
# PRESENT = this watcher took standalone serving down and has not put it back.
# Written the moment quiesce_normal_serving returns, removed by every site here
# that restores. That makes the restore in the refused-precondition branch
# below EDGE-triggered: a refusal that follows a quiesce restores exactly once,
# and every later refusal in the same state is a no-op. A per-tick restore
# instead would kickstart the warmup agent every 30s and hold llama-swap's
# single concurrency slot for the length of each warm — the same starvation the
# pair-wide standdown's own comment records. Beside the other markers because
# the worker-side quiesce record belongs to cluster-quiesce, on the far side of
# CLUSTER_QUIESCE_CMD, and is not readable from here.
quiesce_marker_file="$state_dir/serving-quiesced"

# GENERATION PARITY FIRST — RULE 2. Read (cached, one ls-remote per
# CLUSTER_GENERATION_CHECK_SECS) before ANY other step of the tick, because
# every later step's behaviour depends on the generation: link prep aliases
# what the deployed activation says, quiesce and rank start assemble the stack
# the deployed revision defines. Until 2026-08-01 the only parity check lived
# in cluster-join, which is human-initiated — so a drifted node stayed drifted
# for 86 hours. Now: reported every tick and paged once per distinct drift (see
# generation_heal_maybe in cluster-generation-heal.sh). It is NOT auto-rebuilt:
# a rebuild fired from this agent's own process would be SIGKILLed by the very
# activation it triggers the moment this agent's own launchd plist content
# changes (nix-darwin's launchd activation unloads a changed agent before
# loading the new one), and — independent of that — the parity check has no
# way to know what a differently-deployed host (e.g. a private wrapper flake)
# should be rebuilt INTO. tests/test-generation-heal.sh enforces this as a
# regression: no shipped cluster script may ever call `darwin-rebuild switch`.
# While drift persists, rank_start_preconditions_ok refuses to start (hard
# gate) and the down path below refuses to run link prep from the stale
# generation. Deploying a drifted host is still a deliberate, human-run
# `darwin-rebuild switch`.
parity_now="$(generation_parity_cached "$gen_parity_file")"
generation_drift_report "$parity_now" "$gen_alerted_file"
generation_heal_maybe "$parity_now" "$heal_attempts_file" || true

# PUBLISH THIS HOST'S STATE BEFORE ANYTHING ELSE IS DECIDED, and unconditionally
# — halted, link down, generation drifted, all of it. The peer's start guard
# reads this line to decide whether a rendezvous with this host can possibly
# succeed, and the states worth telling it about are exactly the ones where this
# host is NOT going to participate. A publish that only happened on the healthy
# path would go silent precisely when the peer most needs to hear it, and the
# peer would read the silence as "unreachable" and suppress its own start on a
# weaker reason than the true one.
#
# Placed after the parity read because the published generation comes from that
# same cached fact — one ls-remote per interval, not one per publish.
peer_state_write "${CLUSTER_PEER_STATE_FILE:-$state_dir/peer-state.json}" \
  "$parity_now" "$halt_file" "$pd_debt_file" "$mem_dwell_file"

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
  # AUTO RE-ARM, BEFORE THE HALTED BRANCH DECIDES ANYTHING. A pair-wide
  # standdown is deliberately sticky, and until there was a way to observe the
  # peer that stickiness could only be broken by a human replugging a cable that
  # was never out. Now the peer says when it is ready again, and this ends the
  # halt on that evidence.
  #
  # Runs on every up tick rather than only inside the halted branch, and that
  # placement is the fix rather than an accident: with no halt standing it does
  # nothing but delete the last-seen record, which is what makes the FIRST poll
  # of the next halt a transition. Keyed only on the record, a host that halts
  # while its peer was healthy and unchanged throughout would see no transition
  # ever — the exact case that strands a plugged-in pair.
  #
  # It removes only the halt marker, never the latch, so the branch below still
  # routes through halt_clear_accepted and re-verifies every precondition. This
  # is not a bypass; it is an automatic version of the clear an operator would
  # otherwise have to type.
  peer_rearm_maybe "$halt_file" "$halt_latch_file" "$peer_seen_file" \
    "$parity_now" "$pd_debt_file"
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
        "attempts that failed before the rank that settled" "" \
        "${CLUSTER_RANK_ERROR_LOG:-}" "$session_log_offset_file"
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
            if restore_normal_serving; then
              rm -f "$quiesce_marker_file"
            fi
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
    # SOAK BLOCK — extracted and run verbatim by tests/test-soak-busy-vs-wedged.sh.
    # Keep these marker comments exactly as written; the test greps for them.
    if [ "$CLUSTER_ROLE" = "coordinator" ] && [ -f "$warm_file" ] &&
      [ ! -f "$halt_file" ] && [ "${CLUSTER_WARM_RECHECK_SECS:-600}" -gt 0 ]; then
      warmed_at="$("${CLUSTER_STAT_BIN:-/usr/bin/stat}" -f %m "$warm_file" 2> /dev/null || echo 0)"
      if [ "$warmed_at" -gt 0 ] &&
        [ "$(($(date +%s) - warmed_at))" -ge "${CLUSTER_WARM_RECHECK_SECS:-600}" ]; then
        echo "cluster-link: soak re-check (warm marker older than ${CLUSTER_WARM_RECHECK_SECS:-600}s)"
        # REAL GENERATION PROGRESS BEATS EVERY OTHER SIGNAL. new_progress_lines
        # (cluster-peer-observe.sh, the same predicate cluster-peer-liveness.sh's
        # coordinator_tick checks first) counts token/prompt lines the rank's own
        # log emitted since the last read. endpoint_busy only sees an ESTABLISHED
        # connection — which vanishes the moment a client disconnects on its own
        # timeout, even while the backend is still doing real work. A soak probe
        # fired into that gap queues behind the work and times out, misreading a
        # busy-but-healthy pipeline as wedged (2026-08-16: a burst of requests
        # against unloaded models did exactly this). Checked first because it is
        # strictly stronger evidence than a held connection.
        progressed=0
        if [ -n "${CLUSTER_RANK_PROGRESS_LOG:-}" ]; then
          progressed="$(new_progress_lines)"
        fi
        case "$progressed" in
          '' | *[!0-9]*) progressed=0 ;;
        esac
        if [ "$progressed" -gt 0 ]; then
          echo "cluster-link: soak: $progressed new progress line(s) since last tick — real traffic is live, treating as proof of life without probing"
          touch "$warm_file"
          rm -f "$soak_busy_skips_file"
        else
          # NEVER PROBE A BUSY PIPELINE. mlx_lm.server serializes generation and
          # blocks HTTP for its duration, so a 1-token probe fired while a real
          # request is in flight queues behind it and expires on the probe's own
          # timeout — through no fault of the mesh. On 2026-08-08 that killed a
          # healthy pipeline mid-answer: a 22k-token generation had streamed
          # nothing for 181s, the probe expired, the gate declared the rank
          # wedged, and the SIGTERM teardown leaked the wired shard on both hosts.
          # In-flight work IS proof of life; the probe exists to find out whether
          # there is any, and here there demonstrably is.
          #
          # BOUNDED, because a wedged rank holds connections open exactly as a
          # busy one does. After CLUSTER_SOAK_BUSY_SKIP_MAX consecutive deferrals
          # the probe fires anyway — with a timeout that already exceeds the read
          # timeout real clients use, so a genuine long generation still completes
          # inside it and only a true wedge fails.
          #
          # The warm marker is deliberately NOT refreshed on a deferral. Touching
          # it would push the next re-check a full interval into the future on
          # every skip, so a rank that holds a connection forever would never be
          # probed again — the deferral would become the wedge's hiding place.
          # Left stale, the block re-evaluates next tick and the counter advances
          # toward the bound.
          soak_skips=0
          [ -f "$soak_busy_skips_file" ] && soak_skips="$(cat "$soak_busy_skips_file")"
          case "$soak_skips" in
            '' | *[!0-9]*) soak_skips=0 ;;
          esac
          if endpoint_busy && [ "$soak_skips" -lt "${CLUSTER_SOAK_BUSY_SKIP_MAX:-10}" ]; then
            soak_skips=$((soak_skips + 1))
            printf '%s\n' "$soak_skips" > "$soak_busy_skips_file"
            echo "cluster-link: soak: request in flight — probe skipped, busy pipeline is live ($soak_skips/${CLUSTER_SOAK_BUSY_SKIP_MAX:-10} before probing regardless)"
          elif health_gate_soak_probe "$health_gate_file" "$CLUSTER_RANK_URL" "${CLUSTER_MODEL:-}" \
            "${CLUSTER_HEALTH_GATE_TIMEOUT_SECS:-300}"; then
            touch "$warm_file"
            rm -f "$soak_busy_skips_file"
            # A PASS HERE IS THE WHOLE EVIDENCE CHAIN, which is why the settle
            # hangs off this branch and not off the health gate below. Reaching
            # it requires a formed cluster, a passed health gate (the warm
            # marker this block reads is written by nothing else) and now a real
            # completion served by the running pipeline. The cross-boot cause
            # budget exists to stop a host retrying a start it can never
            # complete; a host that just completed one has answered it.
            # Deliberately NOT hooked to the progress-lines branch above: live
            # traffic is proof this rank is alive, not proof it passed a probe.
            pd_cause_settle_on_evidence "$halt_latch_file"
          else
            echo "cluster-link: soak probe FAILED (${HEALTH_GATE_DETAIL:-no detail}); declaring the rank WEDGED and restoring standalone serving" >&2
            halt_write "$halt_file" "$halt_latch_file" "health-gate-soak-fail" \
              "${HEALTH_GATE_DETAIL:-soak completion probe failed}"
            launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
            if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
              set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
            fi
            if restore_normal_serving; then
              rm -f "$quiesce_marker_file"
            fi
            alert "$(hostname -s): cluster rank failed its periodic soak health-check (${HEALTH_GATE_DETAIL:-no detail}); torn down to standalone serving. Replug the link to retry." \
              "mlx-cluster rank wedged (soak)"
          fi
        fi
      fi
    fi
    # END SOAK BLOCK

    # THE WORKER'S OWN TEARDOWN TRIGGER. Everything above that can tear a wedged
    # pair down — readiness, the health gate, the soak — is coordinator-gated,
    # because only rank 0 binds the endpoint those checks probe. A worker has no
    # endpoint to probe and therefore had no escalation of its own at all: when
    # the coordinator halts while this worker's rank process and its TCP session
    # both survive, the worker sits inside a JACCL all-reduce that its peer has
    # already abandoned, forever, with every local signal reading healthy.
    #
    # The coordinator publishes its halt in the same peer-state document the
    # start gate already reads, so the evidence needs no new channel — just a
    # read of .halted_cause on this side.
    #
    # STRIKES, AND ONLY ON A POSITIVE READ. A fetch that fails is NOT a strike:
    # unreachability is peer-liveness's verdict to reach, not this detector's,
    # and counting a network blip here would tear down healthy pairs. A clean
    # read clears the count, so only a halt the coordinator keeps reporting
    # across CLUSTER_PEER_HALT_STRIKES consecutive checks stands this rank down.
    #
    # On the soak's cadence (CLUSTER_WARM_RECHECK_SECS), not the 30s tick: the
    # coordinator's halt is a sustained condition, and a fetch per tick buys
    # nothing but traffic. The worker times itself off its own check marker.
    #
    # WORKER PEER-HALT BLOCK — extracted and run verbatim by
    # tests/test-peer-halt-standdown.sh. Keep these marker comments exactly as
    # written, indentation included; the test greps for them.
    if [ "$CLUSTER_ROLE" != "coordinator" ] && [ -f "$started_file" ] &&
      [ ! -f "$halt_file" ] && [ "${CLUSTER_WARM_RECHECK_SECS:-600}" -gt 0 ] &&
      peer_state_enabled; then
      settle="$("${CLUSTER_STAT_BIN:-/usr/bin/stat}" -f %m "$started_file" 2> /dev/null || echo 0)"
      last_check=0
      [ -f "$peer_halt_check_file" ] &&
        last_check="$("${CLUSTER_STAT_BIN:-/usr/bin/stat}" -f %m "$peer_halt_check_file" 2> /dev/null || echo 0)"
      if [ "$settle" -gt 0 ] &&
        [ "$(($(date +%s) - settle))" -ge "${CLUSTER_RANK_SETTLE_SECS:-60}" ] &&
        [ "$(($(date +%s) - last_check))" -ge "${CLUSTER_WARM_RECHECK_SECS:-600}" ]; then
        touch "$peer_halt_check_file"
        if ! peer_state_fetch; then
          echo "cluster-link: peer-halt check: peer state unreadable — NO strike (an unreachable peer is peer-liveness's verdict, not this one's)"
        else
          peer_cause="$(printf '%s' "$PEER_STATE_RAW" | jq -r '.halted_cause // "null"' 2> /dev/null || echo null)"
          if [ -z "$peer_cause" ] || [ "$peer_cause" = null ]; then
            rm -f "$peer_halt_strikes_file"
            echo "cluster-link: peer-halt check: peer reports no halt; strikes cleared"
          else
            peer_halt_strikes=0
            [ -f "$peer_halt_strikes_file" ] && peer_halt_strikes="$(cat "$peer_halt_strikes_file")"
            case "$peer_halt_strikes" in
              '' | *[!0-9]*) peer_halt_strikes=0 ;;
            esac
            peer_halt_strikes=$((peer_halt_strikes + 1))
            printf '%s\n' "$peer_halt_strikes" > "$peer_halt_strikes_file"
            echo "cluster-link: peer-halt check: peer HALTED ($peer_cause) while this rank is settled ($peer_halt_strikes/${CLUSTER_PEER_HALT_STRIKES:-2})"
            if [ "$peer_halt_strikes" -ge "${CLUSTER_PEER_HALT_STRIKES:-2}" ]; then
              echo "cluster-link: peer has been halted for $peer_halt_strikes consecutive checks; standing this rank down so the pair re-arms together (a jaccl group cannot re-admit a rank)"
              # Same shape and same order as the rendezvous-absent standdown
              # above: halt FIRST so the next tick does not immediately restart
              # into the same abandoned group, SIGTERM (never SIGKILL — a killed
              # rank leaks its wired shard), ceiling back, serving back, page.
              halt_write "$halt_file" "$halt_latch_file" "peer-halted" \
                "peer reported halted_cause=$peer_cause across $peer_halt_strikes consecutive checks"
              launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
              rm -f "$started_file" "$ready_file" "$warm_file" "$peer_halt_strikes_file"
              if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
                set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
              fi
              restore_normal_serving || true
              alert "$(hostname -s): peer reported itself halted ($peer_cause) while this rank was still in the group; this rank was stood down and the host restored to standalone serving so both sides re-arm on the same start boundary. peer_rearm_maybe clears this halt on its own once the peer reports armed again." \
                "mlx-cluster worker standdown (peer halted)"
            fi
          fi
        fi
      fi
    fi
    # END WORKER PEER-HALT BLOCK

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
        "${CLUSTER_HEALTH_GATE_TIMEOUT_SECS:-300}" "${CLUSTER_HEALTH_GATE_CONCURRENCY:-2}" \
        "${CLUSTER_HEALTH_GATE_CONCURRENT_TIMEOUT_SECS:-360}" "${CLUSTER_WIRED_LIMIT_MB:-0}"; then
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
          if restore_normal_serving; then
            rm -f "$quiesce_marker_file"
          fi
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
    # SAY SO, EVERY TICK. This branch used to be entirely silent: the three
    # helpers above always return 0 and the body only reboots, so a halted
    # watcher exited 0 every tick writing nothing to stdout OR stderr. On
    # 2026-08-07 that hid two live halts for 14 and 28 minutes while every
    # health signal read green — the same failure the already-down probe branch
    # was fixed for. Cheap and unconditional beats a cadence: one line per tick
    # is the whole cost, and the operator needs the CLEAR CONDITION, not just
    # the cause, because a boot-scoped verdict and a link-scoped one look
    # identical in the marker.
    case "$(cat "$halt_latch_file" 2> /dev/null)" in
      pd-debt-exhausted | rank-start-failures)
        halt_clear_hint="only a reboot returns the leaked domains" ;;
      *)
        halt_clear_hint="clears on a link cycle, cluster-join, or a reboot" ;;
    esac
    echo "cluster-link: HALTED ($(cat "$halt_latch_file" 2> /dev/null || echo unknown)) — rank starts suppressed; $halt_clear_hint. $(cat "$halt_file" 2> /dev/null)"
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
        "$kicks consecutive failed distributed inits, one protection domain each" "" \
        "${CLUSTER_RANK_ERROR_LOG:-}" "$session_log_offset_file"
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
      if restore_normal_serving; then
        rm -f "$quiesce_marker_file"
      fi
      # Report the cost as a fraction of the device's own budget, not as a bare
      # count of failed starts: the operator needs to know how much of an
      # eleven-domain pool this just spent, not only that a counter hit its cap.
      alert "$(hostname -s): cluster rank failed $kicks consecutive starts; $(pd_debt_phrase "$(pd_debt_count "$pd_debt_file")" "${CLUSTER_MAX_KICKSTARTS:-?}"). Kickstarts halted and the host restored to standalone serving. This cause (rank-start-failures) is errno-agnostic — an ETIMEDOUT peer-not-there is the common case, but the same 3-strike halt also catches a near-instant EHOSTUNREACH from a Local Network Privacy block (macOS 'nehelper' failing to resolve the rank identity's display metadata), which only a reboot clears. Replug the link to reset, or clear the rank-halted marker — the watcher re-verifies the cause before retrying and will re-halt if it persists. On a FileVault-off host this halt auto-reboots itself; see pd_auto_reboot_if_warranted." \
        "mlx-cluster rank halted (PD guard)"
    elif fast_fail_standdown "$halt_file" "$halt_latch_file" \
      "$fast_fail_strikes_file" "$kicks" "$started_file" "$rank_log_offset_file"; then
      # Stood down: repeated starts died before settling and never reached
      # rendezvous. Ahead of the preconditions deliberately — the alignment hold
      # lives in there, and a peer that is not coming should cost no wait, the
      # same "no wait wasted" ordering rungs 1b and 1c already use.
      :
    elif ! rank_start_preconditions_ok; then
      # A precondition that is not yet met is NOT a failed start: nothing was
      # launched, so no protection domain leaked, so no attempt is consumed.
      # Retry next tick. The function logs which rung failed.
      #
      # BUT A REFUSAL HERE AFTER A QUIESCE SERVES NOTHING AT ALL. A precondition
      # can start passing and then stop — an alignment hold, a peer that stops
      # publishing, a parity change — so a tick that quiesced and kickstarted
      # can be followed by ticks that refuse before ever reaching the quiesce
      # block again. No halt is written (correctly: nothing failed), so nothing
      # else on this path restores, and the host serves neither a rank nor
      # standalone for as long as the rung stays refused.
      #
      # REFUSAL RESTORE BLOCK — extracted and run verbatim by
      # tests/test-quiesce-restore.sh. Keep this marker and its matching
      # "# END REFUSAL RESTORE BLOCK" line exactly as written, indentation
      # included; the test's awk range depends on both.
      if [ ! -f "$quiesce_marker_file" ]; then
        echo "cluster-link: rank start refused; standalone serving was not quiesced by this watcher, nothing to restore"
      elif rank_process_running; then
        echo "cluster-link: rank start refused; a rank process is still running, so it — not standalone serving — owns this host's memory"
      elif restore_normal_serving; then
        rm -f "$quiesce_marker_file"
        echo "cluster-link: rank start refused after a quiesce and no rank survives; standalone serving restored"
      else
        echo "cluster-link: WARN rank start refused after a quiesce and no rank survives; failed to restore standalone serving, retrying next tick" >&2
      fi
      # END REFUSAL RESTORE BLOCK
    else
      # QUIESCE-THEN-START BLOCK — extracted and run verbatim by
      # tests/test-quiesce-restore.sh, which pins that a refusal AFTER
      # quiesce_normal_serving (room check or kickstart failure) always calls
      # restore_normal_serving before falling through. Keep this comment and
      # its matching "# END QUIESCE-THEN-START BLOCK" marker in place; the
      # test's awk range depends on both.
      #
      # Quiesce BEFORE every (re)start, not only on the down->up edge: the
      # link-state file survives a reboot, so a host that boots with the
      # cable in arrives here as up->up with standalone serving warm — skipping the
      # quiesce there is how a rank shard and the standalone models end up wired
      # into the same 128 GB. Both hooks are idempotent, so a mid-run rank
      # restart re-running them is a no-op.
      quiesce_normal_serving
      touch "$quiesce_marker_file"
      # THE ROOM CHECK RUNS HERE, AFTER QUIESCE, NOT AS A rank_start_preconditions_ok
      # RUNG. It used to run ahead of quiesce_normal_serving and could only ever
      # measure memory still held by standalone serving — exactly the memory
      # quiescing exists to return — so it only ever passed by luck. It cannot
      # move quiesce_normal_serving INTO the guard function either: that call is
      # role-conditional on $CLUSTER_NORMAL_PROXY, which is not part of the guard
      # contract every rank-guard test pins, and doing so crashed a test outright
      # under `set -o nounset`. So quiesce stays exactly where it already ran, and
      # this checks what it actually freed. Same "no attempt consumed" contract as
      # every other rung: nothing is launched on a refusal, so nothing leaks and
      # the next tick retries. See rank_start_room_ok's own comment for the fuller
      # account (cluster-link-guards.sh).
      if ! rank_start_room_ok; then
        # QUIESCE ALREADY RAN. Serving is down and no rank is going to replace
        # it — this refusal costs no protection domain, but left here it costs
        # Hermes every request that would have landed on standalone serving
        # until the next tick's quiesce (a no-op, already unloaded) happens to
        # pass. Put serving back now, not "eventually on some later tick".
        echo "cluster-link: $MEM_HEADROOM_DETAIL; NOT starting the rank (no attempt consumed); restoring the standalone serving quiesce just took down" >&2
        if restore_normal_serving; then
          rm -f "$quiesce_marker_file"
          echo "cluster-link: standalone serving restored after the room check refused"
        else
          echo "cluster-link: WARN failed to restore standalone serving after the room check refused; retrying next tick" >&2
        fi
      else
        echo "cluster-link: rank not running; kickstarting (attempt $((kicks + 1)))"
        rm -f "$started_file" "$ready_file" "$warm_file" "$warm_fails_file"
        # Baseline BEFORE the launch, not after: fast_fail_standdown's stage
        # classifier must only see what THIS attempt itself appends. A missing
        # log (fresh boot, nothing has ever run) reads as offset 0, which is
        # correct — everything the attempt writes is "new".
        wc -c < "${CLUSTER_RANK_ERROR_LOG:-/dev/null}" 2> /dev/null > "$rank_log_offset_file" ||
          printf '0\n' > "$rank_log_offset_file"
        # session_log_offset_file gets the SAME baseline, but ONLY on the run's
        # FIRST kickstart (kicks was 0 going in) — every later kickstart in the
        # same run leaves it alone, so it keeps describing where the run started
        # rather than sliding forward with each attempt. See its own definition
        # above for why pd_debt_settle_counter needs the whole run, not the
        # latest attempt.
        if [ "$kicks" -le 0 ]; then
          cp -f "$rank_log_offset_file" "$session_log_offset_file"
        fi
        # COUNT LAUNCHED ATTEMPTS, NOT ISSUED COMMANDS. The counter's stated
        # invariant (cluster-pd-settle.sh) is "launched attempts whose
        # protection-domain cost is not yet on the ledger", and every reset path
        # settles it into the ledger as one leaked domain each. So counting a
        # kickstart that did not launch anything FABRICATES debt, which is as
        # damaging as losing it: enough of them reach the cap, halt the host and
        # can hand pd_auto_reboot_if_warranted a reboot to issue for domains that
        # were never spent. The case is real now that cluster-detach boots the
        # rank job out for the length of a teardown — kickstart against an
        # unloaded service fails, launches nothing, and leaks nothing.
        if launchctl kickstart "gui/$uid/$CLUSTER_RANK_LABEL"; then
          printf '%s\n' "$((kicks + 1))" > "$kicks_file"
        else
          # SAME REASONING AS THE ROOM-CHECK REFUSAL ABOVE: quiesce already ran,
          # nothing launched to replace it, so standalone serving stays down
          # for nothing unless this restores it.
          echo "cluster-link: kickstart of $CLUSTER_RANK_LABEL FAILED; nothing launched, so no attempt is consumed and no domain was spent (the job is usually unloaded — cluster-detach boots it out for the length of a teardown); restoring standalone serving" >&2
          if restore_normal_serving; then
            rm -f "$quiesce_marker_file"
            echo "cluster-link: standalone serving restored after the kickstart failure"
          else
            echo "cluster-link: WARN failed to restore standalone serving after the kickstart failure; retrying next tick" >&2
          fi
        fi
      fi
      # END QUIESCE-THEN-START BLOCK
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
  # BILLED TO THE REASON, NOT ONLY TO THE MECHANISM. source=link-cycle is what
  # settled the counter; it is not what those attempts were spent ON, and the
  # cross-boot cause budget (cluster-pd-cause.sh) is keyed on the reason.
  #
  # Without this the budget can never fill for the cause it most needs to
  # bound. A standdown — fast-fail or pair-wide — writes the latch and leaves
  # the counter outstanding for whichever reset arrives next, which on a real
  # unplug is this one. Every domain those attempts spent would then land in a
  # "link-cycle" bucket that no halt latch ever names, and pd_cause_total
  # peer-absent would read zero forever while the same defect burned a fresh
  # budget every boot. The latch is the only record of the reason that survives
  # to this point, and it is deleted on the next line — so it is read here.
  link_cycle_cause="$(cat "$halt_latch_file" 2> /dev/null || echo '')"
  link_cycle_cause="${link_cycle_cause%%[[:space:]]*}"
  pd_debt_settle_counter "$pd_debt_file" "$kicks_file" 0 "link-cycle" \
    "attempts outstanding when the link went down and reset the session" \
    "${link_cycle_cause:-link-cycle}" "${CLUSTER_RANK_ERROR_LOG:-}" "$session_log_offset_file"
  rm -f "$halt_file" "$halt_latch_file" "$started_file" "$ready_file" \
    "$warm_file" "$warm_fails_file" "$mem_dwell_file" "$fast_fail_strikes_file" \
    "$rank_log_offset_file" "$soak_busy_skips_file"
  launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
  if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
    set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || down_failed=1
  fi
  if restore_normal_serving; then
    rm -f "$quiesce_marker_file"
  else
    down_failed=1
  fi
fi

# HEARTBEAT — A HEALTHY WATCHER AND A DEAD ONE MUST NOT LOG THE SAME THING.
#
# Every branch above logs only when it decides something. A nominal tick — link
# up, rank running and serving, nothing to converge — decides nothing and so
# writes nothing at all, which makes a watcher that is ticking perfectly and one
# that stopped being scheduled byte-identical in the log. That ambiguity is what
# turned each of the silent-guard incidents into an hours-long one: the absence
# of lines read as health.
#
# So: one line every CLUSTER_HEARTBEAT_EVERY ticks, unconditionally, carrying
# the four facts anyone asks for first. Its ABSENCE is now the alarm. The
# odometer is bumped on EVERY tick, including the noisy ones, so a gap in the
# numbering is itself evidence of missed ticks.
heartbeat_ticks=0
[ -f "$heartbeat_file" ] && heartbeat_ticks="$(cat "$heartbeat_file" 2> /dev/null || echo 0)"
case "$heartbeat_ticks" in
  '' | *[!0-9]*) heartbeat_ticks=0 ;;
esac
heartbeat_ticks=$((heartbeat_ticks + 1))
printf '%s\n' "$heartbeat_ticks" > "$heartbeat_file"
heartbeat_every="${CLUSTER_HEARTBEAT_EVERY:-20}"
case "$heartbeat_every" in
  '' | *[!0-9]*) heartbeat_every=20 ;;
esac
if [ "$heartbeat_every" -gt 0 ] && [ "$((heartbeat_ticks % heartbeat_every))" -eq 0 ]; then
  # Three-valued, like every other rank report here: "could not answer" is a
  # different operator action from "not running" (see cluster-rank-status.sh).
  if rank_process_running; then
    heartbeat_rank="running"
  elif rank_process_absent; then
    heartbeat_rank="none"
  else
    heartbeat_rank="UNKNOWN (process probe could not answer)"
  fi
  # Wired, not free: it is the number that says whether a previous rank leaked
  # its shard, and the one a reader needs before believing the rank column.
  # mem_stat_mb prints "<free_mb> <wired_mb>" (cluster-link-guards.sh).
  if heartbeat_mem="$(mem_stat_mb)"; then
    heartbeat_wired="$((${heartbeat_mem#* } / 1024))GiB"
  else
    heartbeat_wired="unreadable (vm_stat)"
  fi
  echo "cluster-link: HEARTBEAT tick $heartbeat_ticks — link $cur, rank $heartbeat_rank, wired $heartbeat_wired (one line per $heartbeat_every ticks; a missing heartbeat means the watcher is not running)"
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
