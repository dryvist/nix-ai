# Night-cluster link watcher — one state-machine tick per launchd interval.
#
# Detects the Thunderbolt point-to-point link by auto-detecting the cabled
# port and discovering the peer's link-local address (or, in fallback mode,
# pinging the static peer IP), then converges the night rank to match:
#   link down -> up : quiesce day serving, start the night rank
#   link up   -> up : ensure the rank is still running (crash recovery)
#   link up -> down : stop the rank, restore day serving
#
# Consumed environment (set declaratively by the launchd agent):
#   NIGHT_ROLE            coordinator | worker
#   NIGHT_LINK_DISCOVERY  link-local (default) | static
#   NIGHT_STATIC_PEER_IP  static-mode peer address (fallback mode only)
#   NIGHT_IFACE_OVERRIDE  optional cabled-port override
#   NIGHT_RANK_LABEL      launchd label of the night rank agent
#   NIGHT_WARMUP_LABEL    launchd label of the day-serving warmup one-shot
#   NIGHT_DAY_PROXY       day llama-swap base URL (coordinator only)
#   NIGHT_STATE_FILE      where the last observed link state is kept
#   NIGHT_QUIESCE_CMD     optional worker-side quiesce hook (run via sh -c)
#   NIGHT_RESTORE_CMD     optional worker-side restore hook (run via sh -c)
#   NIGHT_MAX_KICKSTARTS  consecutive failed rank starts before halting
#   NIGHT_ALERT_URL_FILE  local file holding an ntfy-style URL for the halt
#                         alert (untracked — never commit the URL)
#
# (night_detect_iface / night_peer_ll come from night-link-lib.sh, prepended
# at build time.)

mkdir -p "$(dirname "$NIGHT_STATE_FILE")"
prev="down"
[ -f "$NIGHT_STATE_FILE" ] && prev="$(cat "$NIGHT_STATE_FILE")"

cur="down"
if iface="$(night_detect_iface)"; then
  case "${NIGHT_LINK_DISCOVERY:-link-local}" in
    static)
      if /sbin/ping -c 1 -t 2 -q "$NIGHT_STATIC_PEER_IP" > /dev/null 2>&1; then
        cur="up"
      fi
      ;;
    *)
      if [ -n "$(night_peer_ll "$iface")" ]; then
        cur="up"
      fi
      ;;
  esac
fi

uid="$(id -u)"

if [ "$cur" = "up" ]; then
  if [ "$prev" = "down" ]; then
    echo "night-link: down -> up ($NIGHT_ROLE); quiescing day serving"
    if [ "$NIGHT_ROLE" = "coordinator" ]; then
      # Unload every day model; the day proxy itself stays up so the morning
      # restore only needs a re-warm, not a proxy restart.
      curl -fsS -m 60 -X POST "$NIGHT_DAY_PROXY/api/models/unload" || true
    elif [ -n "${NIGHT_QUIESCE_CMD:-}" ]; then
      sh -c "$NIGHT_QUIESCE_CMD" || true
    fi
  fi
  # Converge every tick while the link is up: restart a crashed rank — but
  # CAP the retries. Every failed `mx.distributed.init()` leaks a kernel
  # RDMA Protection Domain and exhaustion is reboot-only (ml-explore/mlx
  # #3207, exo-explore/exo#1847), so an unbounded crash loop turns one bad
  # start into a forced reboot. After the cap: halt and page once.
  kicks_file="$(dirname "$NIGHT_STATE_FILE")/rank-kickstarts"
  halt_file="$(dirname "$NIGHT_STATE_FILE")/rank-halted"
  if launchctl print "gui/$uid/$NIGHT_RANK_LABEL" 2>/dev/null | grep -q "state = running"; then
    rm -f "$kicks_file" "$halt_file"
  elif [ -f "$halt_file" ]; then
    : # halted — no more PD-burning retries until link cycles or manual clear
  else
    kicks=0
    [ -f "$kicks_file" ] && kicks="$(cat "$kicks_file")"
    if [ "$kicks" -ge "${NIGHT_MAX_KICKSTARTS:-3}" ]; then
      echo "night-link: rank failed $kicks consecutive starts; HALTING kickstarts (RDMA PD guard)"
      touch "$halt_file"
      if [ -f "${NIGHT_ALERT_URL_FILE:-}" ]; then
        curl -fsS -m 10 -H "Priority: urgent" -H "Title: mlx-night rank halted (PD guard)" \
          -d "$(hostname -s): night rank failed $kicks consecutive starts; kickstarts halted to protect RDMA protection domains. errno 60 = reboot needed. Clear: rm the rank-halted marker or replug the link." \
          "$(cat "$NIGHT_ALERT_URL_FILE")" || true
      fi
    else
      echo "night-link: rank not running; kickstarting (attempt $((kicks + 1)))"
      launchctl kickstart "gui/$uid/$NIGHT_RANK_LABEL" || true
      printf '%s\n' "$((kicks + 1))" > "$kicks_file"
    fi
  fi
elif [ "$prev" = "up" ]; then
  echo "night-link: up -> down ($NIGHT_ROLE); restoring day serving"
  # A link cycle (replug) clears the PD-guard state for the next window.
  rm -f "$(dirname "$NIGHT_STATE_FILE")/rank-kickstarts" "$(dirname "$NIGHT_STATE_FILE")/rank-halted"
  launchctl kill SIGTERM "gui/$uid/$NIGHT_RANK_LABEL" 2> /dev/null || true
  if [ "$NIGHT_ROLE" = "coordinator" ]; then
    # Re-warm the declared preload list through the existing warmup one-shot.
    launchctl kickstart -k "gui/$uid/$NIGHT_WARMUP_LABEL" || true
  elif [ -n "${NIGHT_RESTORE_CMD:-}" ]; then
    sh -c "$NIGHT_RESTORE_CMD" || true
  fi
fi

printf '%s\n' "$cur" > "$NIGHT_STATE_FILE"
