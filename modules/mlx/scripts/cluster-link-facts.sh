# shellcheck shell=bash
# Cluster link watcher — OBSERVED FACTS, and the self-heal that acts on them.
#
# THE 86-HOUR DEFECT, in two halves.
#
# Half one, the message. While the link was down the watcher logged, 10,440
# times:
#
#   "cable out, OR this host cannot reach the peer subnet at all (check: ping
#    works from a shell but not from this agent = denied macOS Local Network
#    permission)"
#
# Neither was true. The cable was seated and a Thunderbolt port had carrier the
# whole time; the host had simply never had its own link address aliased onto it,
# because the node had drifted off the deployed generation and the activation
# that does the aliasing never ran. A two-item cause list omitting the real cause
# is worse than no list: a reader picks one of the two and diagnoses the wrong
# machine. So this file emits MEASURED STATE — per-port carrier, where (if
# anywhere) the self address lives, generation parity, whether the peer answered
# — and no guesses. An enumerated cause list is never exhaustive; observed fields
# are.
#
# Half two, the repair. The watcher probed the peer, failed, logged, and never
# once looked at its OWN link prep — the one thing it could have fixed. It had
# the repair already: rank_start_preconditions_ok calls repair_link_prep, but
# only on the link-UP path, which is unreachable when the missing address is what
# makes the link look down. link_prep_self_heal below closes that loop by calling
# the SAME repair (./cluster-link-guards.sh), bounded so it cannot thrash.
#
# Function definitions ONLY. Concatenated into the watcher alongside
# ./cluster-link-locate.sh, ./cluster-link-repair.sh, ./cluster-link-guards.sh
# and ./cluster-generation-parity.sh, whose functions it calls.
#
# Consumed environment:
#   CLUSTER_STATIC_SELF_IP        this host's static link address
#   CLUSTER_STATIC_PEER_IP        peer's static link address
#   CLUSTER_LINK_PREP_MAX_REPAIRS consecutive self-heal attempts before the
#                               watcher stops retrying and just reports (the
#                               counter resets the moment prep is healthy)
#   CLUSTER_IFCONFIG_BIN          ifconfig path (test seam; /sbin is not on a
#                               writeShellApplication PATH)

# Per-port carrier, verbatim from the only authoritative field.
#
# `RUNNING` in the ifconfig flags is NOT carrier — it is set on an
# administratively-up interface with nothing plugged in, and reading it as
# "cable in" is how a dead link reads as healthy. bridge0's own status is
# irrelevant: the cluster deliberately frees the Thunderbolt ports FROM bridge0,
# so an empty, inactive bridge0 is the CORRECT state, not evidence of a problem.
tb_carrier_facts() {
  local dev out state any=0
  while IFS= read -r dev; do
    [ -n "$dev" ] || continue
    any=1
    state=inactive
    out="$("${CLUSTER_IFCONFIG_BIN:-/sbin/ifconfig}" "$dev" 2> /dev/null || true)"
    case "$out" in
      *"status: active"*) state=active ;;
    esac
    printf '%s=%s ' "$dev" "$state"
  done < <(tb_devices)
  [ "$any" = 1 ] || printf 'none '
}

# Where this host's link address is, as a fact rather than a verdict.
self_ip_fact() {
  local dev
  dev="$(iface_holding_self_ip)"
  if [ -n "$dev" ]; then
    printf 'on %s' "$dev"
  else
    printf 'NOT-ALIASED'
  fi
}

# The whole observable state of the link in one line, ordered so the fields read
# in causal order: what the ports see, where our address is, whether prep is
# usable, whether the peer answered, and whether this node is even running the
# generation that configures any of it.
#
# Generation parity with a TTL, because the watcher ticks every 30s and the
# underlying check reaches GitHub. One `git ls-remote` per tick would be ~2900
# network calls a day and would make the facts line flap with the network rather
# than with the system state it is supposed to report.
#
# Cache format is `<epoch> <fact>` on one line — deliberately NOT the file's
# mtime, which would need `stat -f %m` (macOS-only) and make this untestable off
# a Mac. Age is read from the payload, so the same code runs everywhere.
#
# $1 = cache file. TTL from CLUSTER_GENERATION_CHECK_SECS (default 1h) — this is
# also the proactive drift check the watcher never had: it runs on the timer,
# unattended, on both machines.
generation_parity_cached() {
  local cache="$1" ttl="${CLUSTER_GENERATION_CHECK_SECS:-3600}" line stamp now fact
  now="$(date +%s)"
  if [ -f "$cache" ]; then
    line="$(cat "$cache" 2> /dev/null || true)"
    stamp="${line%% *}"
    case "$stamp" in
      '' | *[!0-9]*) stamp=0 ;;
    esac
    if [ "$stamp" -gt 0 ] && [ "$((now - stamp))" -lt "$ttl" ]; then
      printf '%s' "${line#* }"
      return 0
    fi
  fi
  fact="$(generation_parity_fact)"
  printf '%s %s\n' "$now" "$fact" > "$cache"
  printf '%s' "$fact"
}

# Page ONCE per distinct drift, not once per tick.
#
# Drift is the condition that silently disarmed link prep for 86 hours, and
# nothing was watching for it because the only check lived in a command a human
# runs. It is reported here every tick (it is a field of link_facts) and paged
# here at most once per distinct state+revision pair, so a page means "this
# changed", never "the timer fired again".
#
# $1 = the parity fact, $2 = marker holding the last-paged fact.
generation_drift_report() {
  local fact="$1" marker="$2" last=""
  case "$fact" in
    *'state=drift'* | *'state=unstamped'*) ;;
    *)
      rm -f "$marker"
      return 0
      ;;
  esac
  [ -f "$marker" ] && last="$(cat "$marker" 2> /dev/null || true)"
  [ "$fact" = "$last" ] && return 0
  printf '%s\n' "$fact" > "$marker"
  echo "cluster-link: GENERATION $fact — this node is not running the deployed system generation, so any activation-managed cluster state (the Thunderbolt link address above all) may never have been applied. cluster-join heals it." >&2
  alert "$(hostname -s): mlx-cluster generation parity FAILED — $fact. Activation-managed cluster state, including the Thunderbolt link address, may never have been applied on this node. Run cluster-join here to rebuild from the deploy revision." \
    "mlx-cluster generation drift"
}

# $1 = "yes" | "no" — did the peer answer THIS tick (the probe the watcher
# already ran; never re-pinged here, so the line costs nothing extra).
# $2 = generation-parity cache file.
link_facts() {
  local peer_answer="$1" parity_cache="$2" prep carrier
  if link_prep_ok; then
    prep=OK
  else
    carrier="$(first_carrier_tb_device || true)"
    if [ -n "$carrier" ]; then
      # The one inference in this file, and it is definitional rather than a
      # guess: carrier means the cable is in, so a missing address means the prep
      # that assigns it did not run. It says NOTHING about the cable.
      prep="MISSING-WITH-CARRIER(link prep never ran on $carrier; not a cable fault)"
    else
      prep="NO-CARRIER(no Thunderbolt port reports status: active)"
    fi
  fi
  printf 'tb-ports[ %s] self %s %s prep %s peer %s answered=%s generation %s' \
    "$(tb_carrier_facts)" \
    "$CLUSTER_STATIC_SELF_IP" "$(self_ip_fact)" \
    "$prep" \
    "$CLUSTER_STATIC_PEER_IP" "$peer_answer" \
    "$(generation_parity_cached "$parity_cache")"
}

# Repair this host's own link prep, unattended and bounded.
#
# Fires only in the state the incident was actually in: a Thunderbolt port has
# carrier and this host holds no link address on it. No carrier means the cable
# really is out, and there is nothing to repair — attempting one every 30s for
# days would be pure sudo churn.
#
# The cap is on CONSECUTIVE failed attempts and resets the instant prep is
# healthy, so a repair that works costs one attempt and a repair that cannot work
# stops trying instead of thrashing bridge0 membership forever. Reaching the cap
# is not a halt: it stops REPAIRING, never reporting, and any later tick where
# prep succeeds on its own clears the counter.
#
# $1 = counter file. Returns 0 when prep is healthy on exit.
link_prep_self_heal() {
  local counter_file="$1" carrier attempts max
  if link_prep_ok; then
    rm -f "$counter_file"
    return 0
  fi
  carrier="$(first_carrier_tb_device || true)"
  if [ -z "$carrier" ]; then
    return 1
  fi
  max="${CLUSTER_LINK_PREP_MAX_REPAIRS:-3}"
  attempts=0
  [ -f "$counter_file" ] && attempts="$(cat "$counter_file")"
  case "$attempts" in
    '' | *[!0-9]*) attempts=0 ;;
  esac
  if [ "$attempts" -ge "$max" ]; then
    return 1
  fi
  printf '%s\n' "$((attempts + 1))" > "$counter_file"
  echo "cluster-link: SELF-HEAL $carrier has carrier but $CLUSTER_STATIC_SELF_IP is aliased nowhere; repairing link prep (attempt $((attempts + 1))/$max)"
  if repair_link_prep; then
    rm -f "$counter_file"
    return 0
  fi
  return 1
}
