# Night-cluster link watcher — one state-machine tick per launchd interval.
#
# Detects the Thunderbolt point-to-point link by pinging the peer's link
# address, then converges the night rank to match:
#   link down -> up : quiesce day serving, start the night rank
#   link up   -> up : ensure the rank is still running (crash recovery)
#   link up -> down : stop the rank, restore day serving
#
# Consumed environment (set declaratively by the launchd agent):
#   NIGHT_ROLE         coordinator | worker
#   NIGHT_PEER_IP      link address of the other Mac
#   NIGHT_RANK_LABEL   launchd label of the night rank agent
#   NIGHT_WARMUP_LABEL launchd label of the day-serving warmup one-shot
#   NIGHT_DAY_PROXY    day llama-swap base URL (coordinator only)
#   NIGHT_STATE_FILE   where the last observed link state is kept
#   NIGHT_QUIESCE_CMD  optional worker-side quiesce hook (run via sh -c)
#   NIGHT_RESTORE_CMD  optional worker-side restore hook (run via sh -c)

mkdir -p "$(dirname "$NIGHT_STATE_FILE")"
prev="down"
[ -f "$NIGHT_STATE_FILE" ] && prev="$(cat "$NIGHT_STATE_FILE")"

if /sbin/ping -c 1 -t 2 -q "$NIGHT_PEER_IP" > /dev/null 2>&1; then
  cur="up"
else
  cur="down"
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
  # Converge every tick while the link is up: restarts a crashed rank without
  # re-running the quiesce. launchd's ThrottleInterval bounds crash loops.
  if ! launchctl print "gui/$uid/$NIGHT_RANK_LABEL" 2>/dev/null | grep -q "state = running"; then
    echo "night-link: rank not running; kickstarting"
    launchctl kickstart "gui/$uid/$NIGHT_RANK_LABEL" || true
  fi
elif [ "$prev" = "up" ]; then
  echo "night-link: up -> down ($NIGHT_ROLE); restoring day serving"
  launchctl kill SIGTERM "gui/$uid/$NIGHT_RANK_LABEL" 2> /dev/null || true
  if [ "$NIGHT_ROLE" = "coordinator" ]; then
    # Re-warm the declared preload list through the existing warmup one-shot.
    launchctl kickstart -k "gui/$uid/$NIGHT_WARMUP_LABEL" || true
  elif [ -n "${NIGHT_RESTORE_CMD:-}" ]; then
    sh -c "$NIGHT_RESTORE_CMD" || true
  fi
fi

printf '%s\n' "$cur" > "$NIGHT_STATE_FILE"
