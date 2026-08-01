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
#   CLUSTER_MAX_WARM_FAILURES  consecutive post-readiness warm-generation
#                         failures before the rank is declared wedged
#   CLUSTER_WARM_RECHECK_SECS  re-arm the warm marker after this many seconds,
#                         so the wedge detector can run more than once per link
#                         session instead of being disabled by the first
#                         successful warm (default 1800; 0 disables re-checks)
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
down_strikes_file="$state_dir/link-down-strikes"
# Consecutive ticks the PEER's rendezvous session has been absent while this
# rank is running and settled. Drives the pair-wide standdown below.
peer_session_strikes_file="$state_dir/peer-session-strikes"
# Consecutive ticks the probe has failed while the link was ALREADY down. Used
# only to make a permanently-failing probe audible on a cadence — see the
# else-branch of the probe below.
down_quiet_file="$state_dir/link-down-quiet-ticks"
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
  rm -f "$down_strikes_file" "$down_quiet_file"
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
  # cluster could not form. A watchdog whose own failure mode is indistinguishable
  # from "nothing to do" is the certify-by-proxy trap this repo keeps finding.
  #
  # An unplugged cable is a legitimate, possibly days-long down — so this must
  # not spam. Report on a cadence instead: once when down is first confirmed,
  # then every CLUSTER_DOWN_REPORT_EVERY ticks (default 20 ≈ 10 min at the 30s
  # interval). The message names the two causes that look identical from here,
  # because the second one is invisible without it: on macOS a DENIED Local
  # Network permission makes the probe fail with "No route to host" even though
  # the cable is in, the address is assigned and the route and ARP entry are
  # both valid (jevans-ms, 2026-07-25 — shell pinged 75/75 while the agent
  # failed 5/5).
  cur="down"
  downs=0
  [ -f "$down_quiet_file" ] && downs="$(cat "$down_quiet_file")"
  downs=$((downs + 1))
  printf '%s\n' "$downs" > "$down_quiet_file"
  if [ "$downs" -eq 1 ] \
    || [ "$((downs % ${CLUSTER_DOWN_REPORT_EVERY:-20}))" -eq 0 ]; then
    echo "cluster-link: probe to $CLUSTER_STATIC_PEER_IP has failed $downs consecutive tick(s) while down — cable out, OR this host cannot reach the peer subnet at all (check: ping works from a shell but not from this agent = denied macOS Local Network permission). The cluster cannot form until this clears."
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
    # RUNTIME WIRED CEILING. Every rung in rank_start_preconditions_ok is a
    # START precondition, so all of them had already run AND PASSED when this
    # host hard-reset on 2026-08-01: the rank was legal at start, and wired
    # climbed to 96.7 GiB afterwards, until WindowServer's Metal allocation
    # blocked in the GPU driver (IOGPUFamily/AGXG16X) for 80s and the hardware
    # watchdog reset the machine. Nothing watched a rank once it was up.
    #
    # REAP, DO NOT HALT. A halt would be wrong twice over: the breach may be
    # this rank's own live memory, which its exit returns, and a halt would
    # strand the host without the standalone serving restored just below. The
    # persistent case needs no new escalation path — wired that does NOT come
    # back is the unreclaimed-Metal signature, which mem_headroom_ok refuses at
    # the next start, memHeadroomHaltSecs escalates to a halt, and
    # pd_auto_reboot_if_warranted acts on. This rung only has to stop the climb
    # before the compositor starves.
    if ! wired_detail="$(rank_wired_ceiling_ok "${CLUSTER_WIRED_CEILING_MB:-0}")"; then
      echo "cluster-link: $wired_detail" >&2
      launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
      rm -f "$started_file" "$ready_file" "$warm_file"
      if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
        set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
      fi
      restore_normal_serving || true
      alert "$(hostname -s): $wired_detail" \
        "mlx-cluster rank reaped (wired ceiling)"
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
            launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
            rm -f "$started_file" "$ready_file" "$warm_file" "$peer_session_strikes_file"
            if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
              set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
            fi
            restore_normal_serving || true
            alert "$(hostname -s): peer rank vanished; this rank was stood down and the host restored to standalone serving so both sides re-arm on the same start boundary." \
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
    # Re-arm the warm marker periodically so the wedge detector below can run
    # more than once per link session.
    #
    # The detector counts consecutive warm-generation failures and tears the
    # rank down at CLUSTER_MAX_WARM_FAILURES — but the whole block is gated on
    # the warm marker being ABSENT, so a single successful warm disables it for
    # the rest of the session. It therefore catches a rank that wedges BEFORE
    # its first warm and can never catch one that wedges AFTER.
    #
    # After is the case actually observed (2026-07-25). The one-token warm
    # succeeded, the marker was set, and the rank then wedged on a real
    # request: an 8-token completion returned 0 bytes after 900s while both
    # ranks spun at ~100% CPU — the coordinator in jaccl::MeshImpl::recv, the
    # worker in mlx::core::Fence::wait. Readiness stayed latched, the marker
    # stayed set, and nothing escalated for over an hour.
    #
    # Dropping the marker on an interval re-runs the existing probe and its
    # existing failure counting, so no new teardown path is introduced. The
    # interval is deliberately long: mlx_lm.server blocks HTTP during a
    # generation, so a healthy rank mid-answer will fail a probe, and only
    # CLUSTER_MAX_WARM_FAILURES *consecutive* failures escalate.
    if [ "$CLUSTER_ROLE" = "coordinator" ] && [ -f "$warm_file" ] &&
      [ "${CLUSTER_WARM_RECHECK_SECS:-1800}" -gt 0 ]; then
      warmed_at="$(/usr/bin/stat -f %m "$warm_file" 2> /dev/null || echo 0)"
      if [ "$warmed_at" -gt 0 ] &&
        [ "$(($(date +%s) - warmed_at))" -ge "${CLUSTER_WARM_RECHECK_SECS:-1800}" ]; then
        echo "cluster-link: re-checking liveness (warm marker older than ${CLUSTER_WARM_RECHECK_SECS:-1800}s)"
        rm -f "$warm_file"
      fi
    fi

    # First-token warm-up: once the rank is ready, fire one untimed 1-token
    # generation so weights/compile caches are hot before the router flips
    # traffic in. Coordinator-only (only rank 0 binds the endpoint) and
    # idempotent per link session via the rank-warmed marker, which link-down
    # clears. A blocked or failed warm just leaves the marker absent, so the
    # next tick retries — no regression versus not warming.
    if [ "$CLUSTER_ROLE" = "coordinator" ] && [ -f "$ready_file" ] && [ ! -f "$warm_file" ] &&
      [ ! -f "$halt_file" ] && [ -n "${CLUSTER_RANK_URL:-}" ]; then
      echo "cluster-link: rank ready; firing 1-token warm generation"
      if curl -fsS -m 300 -X POST "$CLUSTER_RANK_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"${CLUSTER_MODEL:-}\",\"messages\":[{\"role\":\"user\",\"content\":\"warmup\"}],\"max_tokens\":1,\"stream\":false,\"temperature\":0}" \
        > /dev/null 2>&1; then
        touch "$warm_file"
        rm -f "$warm_fails_file"
      else
        # Readiness is a one-shot latch: /v1/models answering once is never
        # re-verified, so a rank that serves the probe but wedges on real
        # generation (INC-17070) would sit here retrying forever with nothing
        # escalating. Count consecutive post-readiness failures and tear down
        # to standalone at the cap instead of running wedged.
        warm_fails=0
        [ -f "$warm_fails_file" ] && warm_fails="$(cat "$warm_fails_file")"
        warm_fails=$((warm_fails + 1))
        printf '%s\n' "$warm_fails" > "$warm_fails_file"
        if [ "$warm_fails" -ge "${CLUSTER_MAX_WARM_FAILURES:-3}" ]; then
          echo "cluster-link: warm generation failed $warm_fails times after readiness; declaring the rank WEDGED and restoring standalone serving" >&2
          # Reuse the PD-guard halt latch: it already suppresses restarts until
          # the link cycles, so the wedged rank is not immediately restarted.
          halt_write "$halt_file" "$halt_latch_file" "warm-wedged" \
            "$warm_fails consecutive post-readiness warm-generation failures"
          launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
          if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
            set_wired_limit "${CLUSTER_STANDALONE_WIRED_LIMIT_MB:-0}" || true
          fi
          restore_normal_serving || true
          # Through alert(), never a raw curl: this page used to POST an
          # ntfy-style body with Priority/Title HEADERS, which the Slack webhook
          # rejects as invalid_payload — and `-fsS ... || true` then swallowed
          # both the rejection and the message. Silent by construction.
          alert "$(hostname -s): cluster rank answered /v1/models but failed $warm_fails consecutive warm generations; torn down to standalone serving. Replug the link to retry." \
            "mlx-cluster rank wedged (warm generation)"
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
    "$warm_file" "$warm_fails_file" "$mem_dwell_file"
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
