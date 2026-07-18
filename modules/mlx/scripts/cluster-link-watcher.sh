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
#   CLUSTER_ALERT_URL_FILE  local file holding an ntfy-style URL for the halt
#                         alert (untracked — never commit the URL)
#   CLUSTER_HTTP_PORT       coordinator only: cluster endpoint to readiness-probe
#   CLUSTER_LOAD_GRACE_SECS readiness grace for the model load (default 1800)
#   CLUSTER_WIRED_LIMIT_MB  optional: iogpu ceiling to hold while clustered
#                         (applied via the exact-value sudoers grant from
#                         nix-darwin; a failed apply SKIPS the rank start)
#   CLUSTER_DAY_WIRED_LIMIT_MB  restore value at link-down (default 0)

mkdir -p "$(dirname "$CLUSTER_STATE_FILE")"
prev="down"
[ -f "$CLUSTER_STATE_FILE" ] && prev="$(cat "$CLUSTER_STATE_FILE")"

cur="down"
if /sbin/ping -c 1 -t 2 -q "$CLUSTER_STATIC_PEER_IP" > /dev/null 2>&1; then
  cur="up"
fi

uid="$(id -u)"
state_dir="$(dirname "$CLUSTER_STATE_FILE")"
kicks_file="$state_dir/rank-kickstarts"
halt_file="$state_dir/rank-halted"
started_file="$state_dir/rank-first-running"
ready_file="$state_dir/rank-ready"
warm_file="$state_dir/rank-warmed"

# Idempotent wired-ceiling write through the exact-value sudoers grant.
# No-op when unset or already at the target; returns nonzero on failure.
set_wired_limit() {
  local target="$1" current
  [ -n "$target" ] || return 0
  current="$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo '')"
  [ "$current" = "$target" ] && return 0
  if sudo -n /usr/sbin/sysctl -w "iogpu.wired_limit_mb=$target" > /dev/null 2>&1 &&
    [ "$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null)" = "$target" ]; then
    echo "cluster-link: iogpu.wired_limit_mb=$target"
  else
    echo "cluster-link: WARN failed to set iogpu.wired_limit_mb=$target (sudoers grant missing?)" >&2
    return 1
  fi
}

quiesce_normal_serving() {
  if [ "$CLUSTER_ROLE" = "coordinator" ]; then
    # Unload every normal-mode model; the proxy itself stays up so the
    # restore only needs a re-warm, not a proxy restart. Idempotent.
    curl -fsS -m 60 -X POST "$CLUSTER_NORMAL_PROXY/api/models/unload" || true
  elif [ -n "${CLUSTER_QUIESCE_CMD:-}" ]; then
    sh -c "$CLUSTER_QUIESCE_CMD" || true
  fi
}

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
    rm -f "$kicks_file" "$halt_file"
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
    # First-token warm-up: once the rank is ready, fire one untimed 1-token
    # generation so weights/compile caches are hot before the router flips
    # traffic in. Coordinator-only (only rank 0 binds the endpoint) and
    # idempotent per link session via the rank-warmed marker, which link-down
    # clears. A blocked or failed warm just leaves the marker absent, so the
    # next tick retries — no regression versus not warming.
    if [ "$CLUSTER_ROLE" = "coordinator" ] && [ -f "$ready_file" ] && [ ! -f "$warm_file" ] &&
      [ -n "${CLUSTER_RANK_URL:-}" ]; then
      echo "cluster-link: rank ready; firing 1-token warm generation"
      if curl -fsS -m 300 -X POST "$CLUSTER_RANK_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"${CLUSTER_MODEL:-}\",\"messages\":[{\"role\":\"user\",\"content\":\"warmup\"}],\"max_tokens\":1,\"stream\":false,\"temperature\":0}" \
        > /dev/null 2>&1; then
        touch "$warm_file"
      fi
    fi
  elif [ -f "$halt_file" ]; then
    : # halted — no more PD-burning retries until link cycles or manual clear
  else
    kicks=0
    [ -f "$kicks_file" ] && kicks="$(cat "$kicks_file")"
    if [ "$kicks" -ge "${CLUSTER_MAX_KICKSTARTS:-3}" ]; then
      echo "cluster-link: rank failed $kicks consecutive starts; HALTING kickstarts (RDMA PD guard)"
      touch "$halt_file"
      if [ -f "${CLUSTER_ALERT_URL_FILE:-}" ]; then
        curl -fsS -m 10 -H "Priority: urgent" -H "Title: mlx-cluster rank halted (PD guard)" \
          -d "$(hostname -s): cluster rank failed $kicks consecutive starts; kickstarts halted to protect RDMA protection domains. errno 60 = reboot needed. Clear: rm the rank-halted marker or replug the link." \
          "$(cat "$CLUSTER_ALERT_URL_FILE")" || true
      fi
    elif ! set_wired_limit "${CLUSTER_WIRED_LIMIT_MB:-}"; then
      # Never start a rank over a day-sized ceiling: a shard wiring out the
      # GUI working set is the 2026-07-12 dual-host panic. Retry next tick;
      # this does not consume a kickstart attempt.
      echo "cluster-link: wired ceiling not applied; NOT starting the rank"
    else
      # Quiesce BEFORE every (re)start, not only on the down->up edge: the
      # link-state file survives a reboot, so a host that boots with the
      # cable in arrives here as up->up with day serving warm — skipping the
      # quiesce there is how a rank shard and the day models end up wired
      # into the same 128 GB. Both hooks are idempotent, so a mid-run rank
      # restart re-running them is a no-op.
      quiesce_normal_serving
      echo "cluster-link: rank not running; kickstarting (attempt $((kicks + 1)))"
      rm -f "$started_file" "$ready_file" "$warm_file"
      launchctl kickstart "gui/$uid/$CLUSTER_RANK_LABEL" || true
      printf '%s\n' "$((kicks + 1))" > "$kicks_file"
    fi
  fi
elif [ "$prev" = "up" ]; then
  echo "cluster-link: up -> down ($CLUSTER_ROLE); restoring normal serving"
  # A link cycle (replug) clears the PD-guard + readiness state and the warm
  # marker so the next link session re-warms its freshly started rank.
  rm -f "$kicks_file" "$halt_file" "$started_file" "$ready_file" "$warm_file"
  launchctl kill SIGTERM "gui/$uid/$CLUSTER_RANK_LABEL" 2> /dev/null || true
  if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
    set_wired_limit "${CLUSTER_DAY_WIRED_LIMIT_MB:-0}" || true
  fi
  if [ "$CLUSTER_ROLE" = "coordinator" ]; then
    # Re-warm the declared preload list through the existing warmup one-shot.
    launchctl kickstart -k "gui/$uid/$CLUSTER_WARMUP_LABEL" || true
  elif [ -n "${CLUSTER_RESTORE_CMD:-}" ]; then
    sh -c "$CLUSTER_RESTORE_CMD" || true
  fi
fi

printf '%s\n' "$cur" > "$CLUSTER_STATE_FILE"
