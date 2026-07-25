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
# Consecutive ticks the probe has failed while the link was ALREADY down. Used
# only to make a permanently-failing probe audible on a cadence — see the
# else-branch of the probe below.
down_quiet_file="$state_dir/link-down-quiet-ticks"
# Sticky companion to halt_file: survives a manual `rm` of the marker so the
# next tick can re-verify the cause before the first retry (see
# halt_clear_accepted). Cleared only by a real link cycle or an accepted clear.
halt_latch_file="$state_dir/rank-halt-latched"

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
    rm -f "$kicks_file" "$halt_file" "$halt_latch_file"
    if [ ! -f "$started_file" ]; then
      touch "$started_file"
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
  elif [ -f "$halt_file" ]; then
    : # halted — no more PD-burning retries until the link cycles
  elif [ -f "$halt_latch_file" ] &&
    ! halt_clear_accepted "$halt_file" "$halt_latch_file" "$kicks_file"; then
    : # cleared by hand while the cause persists — re-halted, logged, no retry
  else
    kicks=0
    [ -f "$kicks_file" ] && kicks="$(cat "$kicks_file")"
    if [ "$kicks" -ge "${CLUSTER_MAX_KICKSTARTS:-3}" ]; then
      echo "cluster-link: rank failed $kicks consecutive starts; HALTING kickstarts (RDMA PD guard)"
      halt_write "$halt_file" "$halt_latch_file" "rank-start-failures" \
        "$kicks consecutive failed rank starts"
      alert "$(hostname -s): cluster rank failed $kicks consecutive starts; kickstarts halted to protect RDMA protection domains. errno 60 = reboot needed. Replug the link to reset, or clear the rank-halted marker — the watcher re-verifies the cause before retrying and will re-halt if it persists." \
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
  rm -f "$kicks_file" "$halt_file" "$halt_latch_file" "$started_file" "$ready_file" \
    "$warm_file" "$warm_fails_file"
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
