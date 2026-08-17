# shellcheck shell=bash
# Cluster peer state — the cross-host intent channel.
#
# Concatenated after ./cluster-link-guards.sh and given only to the link
# watcher: it is the only component that both PUBLISHES this host's state and
# READS the peer's. The responder that serves the published file
# (./cluster-peer-state-serve.sh) shares no functions with it on purpose — it is
# dumb transport and calls nothing from here.
#
# WHY THIS EXISTS. Until now the two watchers had no channel between them at
# all. Each ping-gated its peer's HOST and then kickstarted its own rank, so
# "the peer is reachable" was the strongest statement either could make before
# spending a protection domain. It is not a strong enough one: a host answers
# ICMP while its own watcher is halted, while it is booting, while it holds no
# link address, while it sits at a memory shortfall it cannot clear, and while
# it runs a different system generation. Every one of those makes a rendezvous
# certain to fail, and a rendezvous that fails leaks one boot-scoped RDMA
# protection domain of eleven. On 2026-08-08 that cost five of them in eighteen
# minutes against a peer that had already stood down.
#
# The fix is to make the peer's INTENT observable before the attempt, not the
# attempt itself the way of finding out. Each host publishes one JSON line; each
# host reads the other's and refuses to start unless it says the peer is armed.
#
# THIS DOES NOT SEQUENCE THE RANKS, and that distinction is load-bearing. The
# 2026-07-25 removal was of a gate that waited for the peer's RANK to be
# LISTENING, which guaranteed this host arrived ~20-30s outside jaccl's fixed
# ~15s connect budget. `armed` is a statement about a host's own readiness that
# is true BEFORE either rank starts, so both sides see it simultaneously and
# both still fire on the shared wall-clock boundary in rank_start_preconditions_ok.
# See the `armed` definition in peer_state_write for why it may never contain a
# peer-derived fact: two hosts each waiting for the other to be ready is a
# deadlock, not a handshake.
#
# Consumed environment:
#   CLUSTER_PEER_STATE_FILE           where this host publishes its own state
#   CLUSTER_PEER_STATE_PORT           peer's responder port; 0/unset = channel
#                                     disabled, and every gate below passes
#   CLUSTER_PEER_STATE_TIMEOUT_SECS   bound on one state fetch
#   CLUSTER_PEER_STATE_STALE_SECS     age past which a fetched state is refused
#   CLUSTER_STATIC_PEER_IP            peer's link address
#   CLUSTER_PD_DEBT_FILE / _MAX       the boot-scoped ledger and its cap
#   CLUSTER_SHARD_MEMORY_MB           drives wired_ok via mem_headroom_ok
#   CLUSTER_CURL_BIN                  curl path (test seam, like CLUSTER_PING_BIN)

# Is the channel configured at all? 0 or unset disables every gate here, the
# same "0 = off" convention CLUSTER_WARM_RECHECK_SECS and
# CLUSTER_PD_AUTO_REBOOT_WINDOW_SECS already use — so a deployment that has not
# rolled the responder out yet behaves exactly as it did before.
peer_state_enabled() {
  case "${CLUSTER_PEER_STATE_PORT:-0}" in
    '' | 0 | *[!0-9]*) return 1 ;;
  esac
  return 0
}

# The committed revision out of a generation-parity fact (see
# ./cluster-generation-parity.sh for the format). Empty when the fact carries no
# local= field, which is what `state=disabled` looks like — and an empty
# generation on BOTH sides compares equal, so disabling parity checking does not
# also wedge this gate.
peer_state_generation() {
  local fact="$1" rev
  case "$fact" in
    *local=*) ;;
    *) return 0 ;;
  esac
  rev="${fact#*local=}"
  rev="${rev%% *}"
  printf '%s' "$rev"
}

# PUBLISH THIS HOST'S STATE. Called unconditionally, once per tick, before the
# link probe — including while halted and while the link is down, because those
# are exactly the states the peer most needs to see. A file that stops being
# written is indistinguishable from a healthy one to the responder, which is why
# every reader below enforces the ts field's freshness rather than trusting the
# file to exist.
#
# `armed` IS A PURE LOCAL FACT. It answers "if my peer started its rank right
# now, would mine be able to join?" and it may never fold in anything derived
# from the peer — no ping, no fetched state, nothing. Both hosts evaluate it
# independently and both reach the same answer at the same time; the moment it
# depends on the peer, two armed hosts each wait for the other forever.
#
# The four terms are the four local conditions that make a rendezvous certain to
# fail, and each one already gates a rank start on this side:
#   no halt marker        — this host has stood itself down
#   PD debt under the cap — this boot has domains left to spend
#   generation parity ok  — mismatched mlx/JACCL stacks cannot mesh
#   memory headroom       — a shard that will not fit dies after allocating a domain
#
# jq builds the JSON; nothing is string-interpolated. A halt detail is
# operator-facing prose full of quotes, and hand-built JSON is how the Slack
# alerter shipped silently-rejected payloads for weeks.
#
# Written to a temp and moved into place, so the responder never cats a
# half-written line.
#
# $1 output file, $2 generation-parity fact, $3 halt marker, $4 PD ledger,
# $5 memory-headroom dwell file (optional — omitted callers get the memory
# term always-armed, same as CLUSTER_SHARD_MEMORY_MB=0).
peer_state_write() {
  local out="$1" parity="$2" halt_file="$3" debt_file="$4" mem_dwell_file="${5:-}"
  local armed=true wired=true cause="" gen boot debt max tmp mem_required mem_dwell
  gen="$(peer_state_generation "$parity")"
  boot="$(current_boot_epoch)"
  case "${boot:-}" in
    '' | *[!0-9]*) boot=0 ;;
  esac
  if [ -f "$halt_file" ]; then
    armed=false
    cause="$(awk -F'\t' '{for (i = 1; i <= NF; i++) if ($i ~ /^cause=/) { sub(/^cause=/, "", $i); print $i; exit }}' "$halt_file" 2> /dev/null || true)"
    [ -n "$cause" ] || cause="unknown"
  fi
  max="${CLUSTER_PD_DEBT_MAX:-0}"
  case "$max" in
    '' | *[!0-9]*) max=0 ;;
  esac
  if [ "$max" -gt 0 ]; then
    debt="$(pd_debt_count "$debt_file")"
    case "${debt:-}" in
      '' | *[!0-9]*) debt=0 ;;
    esac
    [ "$debt" -lt "$max" ] || armed=false
  fi
  case "$parity" in
    *'state=drift'* | *'state=unstamped'*) armed=false ;;
  esac
  # wired_ok is reported separately as well as folded into armed, because it is
  # the one term whose remedy differs: a peer refusing on memory needs a reboot
  # to return unreclaimed wired Metal, where every other term clears on its own.
  # Naming it lets the refusing side's log say which.
  #
  # BOTH a fresh sample AND recent history must clear before this reports
  # armed. A raw mem_headroom_ok call alone catches a brand-new shortfall
  # immediately (unchanged from before); the dwell count alone is what fixes
  # the flapping bug — mem_headroom_halt_if_persistent (cluster-link-guards.sh)
  # decrements it by one per pass rather than zeroing it, so a single lucky
  # sample right after a run of refusals cannot flip armed on its own. Needing
  # BOTH means: dwell>0 blocks armed even when the current sample happens to
  # pass (the flapping case), and a first-ever refusal still blocks armed even
  # before any dwell file exists (the immediate-detection case).
  # No outer "required -gt 0" gate here: mem_headroom_ok already no-ops on a
  # 0/unset requirement internally (the "0 = off" convention), so gating a
  # second time here would only add a second place that convention has to be
  # kept in sync.
  mem_required="${CLUSTER_SHARD_MEMORY_MB:-0}"
  case "$mem_required" in
    '' | *[!0-9]*) mem_required=0 ;;
  esac
  mem_dwell=0
  [ -n "$mem_dwell_file" ] && [ -f "$mem_dwell_file" ] &&
    mem_dwell="$(cat "$mem_dwell_file" 2> /dev/null || echo 0)"
  case "$mem_dwell" in
    '' | *[!0-9]*) mem_dwell=0 ;;
  esac
  if [ "$mem_dwell" -gt 0 ] || ! mem_headroom_ok "$mem_required"; then
    wired=false
    armed=false
  fi
  tmp="$out.tmp"
  mkdir -p "$(dirname "$out")" 2> /dev/null || return 0
  if jq -nc \
    --argjson armed "$armed" \
    --argjson wired "$wired" \
    --argjson boot "$boot" \
    --argjson ts "$(date +%s)" \
    --arg cause "$cause" \
    --arg generation "$gen" \
    '{armed: $armed, halted_cause: (if $cause == "" then null else $cause end), boot: $boot, wired_ok: $wired, generation: $generation, ts: $ts}' \
    > "$tmp" 2> /dev/null; then
    mv -f "$tmp" "$out" 2> /dev/null || true
  else
    rm -f "$tmp" 2> /dev/null || true
    echo "cluster-link: WARN could not publish peer state to $out; the peer will read this host as unreachable and suppress its own starts" >&2
  fi
  return 0
}

# Fetch the peer's published state into PEER_STATE_RAW. Nonzero on anything that
# is not one well-formed JSON object — an empty body, a truncated line, an HTTP
# error — because a gate that treats an unparseable answer as permission is not
# a gate.
#
# THE BINARY IS APPLE'S ON PURPOSE, exactly as peer_reachable pins /sbin/ping.
# The peer sits on the Thunderbolt subnet, which is ON-LINK (a `UC` route on the
# TB interface, never through a router), and macOS Local Network Privacy gates
# on-link connections per-binary while exempting Apple's own. A PATH-resolved
# curl is the Nix one, so this fetch failed instantly — measured 2026-08-16:
# /usr/bin/curl returned the peer's state in 14 ms while the store curl gave
# "Failed to connect after 0 ms" against the same address and port.
#
# It cannot be fixed by granting the store curl permission: a Nix store path
# changes on every rebuild, and the grant is keyed to the binary, so each
# rebuild would silently revoke it. The failure is also invisible in the worst
# way — the peer looks unarmed, so the gate suppresses every start and the
# cluster never forms while both hosts report themselves healthy.
peer_state_fetch() {
  PEER_STATE_RAW=""
  local body
  body="$("${CLUSTER_CURL_BIN:-/usr/bin/curl}" -fsS -m "${CLUSTER_PEER_STATE_TIMEOUT_SECS:-2}" \
    "http://${CLUSTER_STATIC_PEER_IP}:${CLUSTER_PEER_STATE_PORT}/" 2> /dev/null)" || return 1
  [ -n "$body" ] || return 1
  printf '%s' "$body" | jq -e 'type == "object"' > /dev/null 2>&1 || return 1
  PEER_STATE_RAW="$body"
  return 0
}

# THE GATE. 0 = the peer says it is ready and this host may spend a domain.
#
# Sets PEER_GATE_REASON to a stable token on refusal, and leaves PEER_STATE_RAW
# holding whatever was fetched so peer_rearm_maybe can key a transition on it
# without a second round trip.
#
# EVERY REFUSAL IS LOGGED BY THE CALLER, EVERY TICK — never a silent skip. A
# guard that exits 0 without a word is the defect this subsystem has shipped
# more than any other: the already-down probe branch was silent for 65 minutes,
# the halted branch for 28 ticks. A suppressed start is a decision and it says
# so out loud, including that it cost nothing.
#
# $1 this host's generation-parity fact.
peer_armed_ok() {
  local parity="$1" armed wired peer_gen local_gen ts age stale
  PEER_GATE_REASON=""
  peer_state_enabled || return 0
  if ! peer_state_fetch; then
    PEER_GATE_REASON="peer unreachable on ${CLUSTER_STATIC_PEER_IP}:${CLUSTER_PEER_STATE_PORT} — booting, watcher down, or no link address yet"
    return 1
  fi
  # STALENESS IS A REFUSAL. The responder serves whatever file is on disk, so a
  # watcher that died mid-boot would otherwise serve armed=true forever from its
  # last healthy tick — a dead host granting permission to spend domains against
  # it. The window is a multiple of the tick, so a single missed tick is absorbed.
  ts="$(printf '%s' "$PEER_STATE_RAW" | jq -r '.ts // 0' 2> /dev/null || echo 0)"
  case "$ts" in
    '' | *[!0-9]*) ts=0 ;;
  esac
  stale="${CLUSTER_PEER_STATE_STALE_SECS:-0}"
  case "$stale" in
    '' | *[!0-9]*) stale=0 ;;
  esac
  if [ "$stale" -gt 0 ]; then
    age=$(($(date +%s) - ts))
    if [ "$ts" -le 0 ] || [ "$age" -gt "$stale" ]; then
      PEER_GATE_REASON="peer state is ${age}s old (stale past ${stale}s) — its watcher has stopped publishing"
      return 1
    fi
  fi
  armed="$(printf '%s' "$PEER_STATE_RAW" | jq -r '.armed // false' 2> /dev/null || echo false)"
  if [ "$armed" != "true" ]; then
    PEER_GATE_REASON="peer is not armed (halted_cause=$(printf '%s' "$PEER_STATE_RAW" | jq -r '.halted_cause // "none"' 2> /dev/null || echo unknown))"
    return 1
  fi
  wired="$(printf '%s' "$PEER_STATE_RAW" | jq -r '.wired_ok // false' 2> /dev/null || echo false)"
  if [ "$wired" != "true" ]; then
    PEER_GATE_REASON="peer has no memory headroom for its shard — only a reboot returns unreclaimed wired Metal"
    return 1
  fi
  # GENERATION PARITY, PAIRWISE. This host's own parity rung compares against the
  # deploy branch; that answers "am I current", not "do we match each other". Two
  # nodes can both be current and still differ for the minutes between one
  # activating and the other, and a mixed mlx/JACCL stack is the untestable
  # variable behind the INC-17070 deadlock family.
  peer_gen="$(printf '%s' "$PEER_STATE_RAW" | jq -r '.generation // ""' 2> /dev/null || echo '')"
  local_gen="$(peer_state_generation "$parity")"
  if [ "$peer_gen" != "$local_gen" ]; then
    PEER_GATE_REASON="generation mismatch (peer ${peer_gen:-unknown}, local ${local_gen:-unknown}) — a mixed mlx/JACCL stack cannot mesh"
    return 1
  fi
  return 0
}

# AUTO RE-ARM: clear this host's halt when the PEER comes back.
#
# The pair-wide standdown is deliberately sticky — a halted rank stays halted
# until a link cycle, because the alternative is a restart loop that spends a
# domain per pass. That was right when nothing could observe the peer, and it is
# the reason a plugged-in pair could sit halted indefinitely waiting for a human
# to replug a cable that was never out. With the state channel the halt can end
# on evidence instead: the peer says it is armed again, so the reason this host
# stood down no longer holds.
#
# WHAT COUNTS AS A TRANSITION, and why "no record" is one. Keying only on
# unreachable->armed and halted->armed misses the case that actually strands a
# pair: this host halts while the peer was healthy all along, so the peer never
# changes state and no transition ever arrives. The last-seen file is therefore
# deleted whenever no halt stands, so the first poll inside a halt always has no
# record to compare against and fires exactly one re-arm. A peer reboot changes
# the key too, via its boot epoch.
#
# THE CLEAR IS A REQUEST, NOT A FACT. Only the halt marker is removed; the latch
# stays, so the very next tick runs halt_clear_accepted, re-verifies every
# precondition, and re-halts naming whatever still fails. That is the same path a
# by-hand clear takes — no new bypass, and pd-debt-exhausted keeps refusing for
# free. Skipped outright while the boot-scoped ledger is at its cap or the
# cross-boot cause budget is spent: re-arming into a guard that will immediately
# re-halt is churn, and the cause budget exists precisely to stop a loop that
# keeps re-arming.
#
# $1 halt marker, $2 latch, $3 last-seen peer key, $4 parity fact, $5 PD ledger.
peer_rearm_maybe() {
  local halt_file="$1" latch_file="$2" seen_file="$3" parity="$4" debt_file="$5"
  local now_key last_key debt max
  peer_state_enabled || return 0
  if [ ! -f "$halt_file" ]; then
    rm -f "$seen_file"
    return 0
  fi
  if ! peer_armed_ok "$parity"; then
    printf 'notarmed\n' > "$seen_file"
    echo "cluster-link: halted and peer is not armed ($PEER_GATE_REASON) — staying down, 0 protection domains spent"
    return 0
  fi
  now_key="armed boot=$(printf '%s' "$PEER_STATE_RAW" | jq -r '.boot // 0' 2> /dev/null || echo 0)"
  last_key=""
  [ -f "$seen_file" ] && last_key="$(cat "$seen_file" 2> /dev/null || echo '')"
  printf '%s\n' "$now_key" > "$seen_file"
  if [ "$now_key" = "$last_key" ]; then
    return 0
  fi
  max="${CLUSTER_PD_DEBT_MAX:-0}"
  case "$max" in
    '' | *[!0-9]*) max=0 ;;
  esac
  if [ "$max" -gt 0 ]; then
    debt="$(pd_debt_count "$debt_file")"
    case "${debt:-}" in
      '' | *[!0-9]*) debt=0 ;;
    esac
    if [ "$debt" -ge "$max" ]; then
      echo "cluster-link: peer is armed again but $(pd_debt_phrase "$debt" "$max"); NOT re-arming — only a reboot returns a leaked domain" >&2
      return 0
    fi
  fi
  if ! pd_cause_budget_ok "$latch_file"; then
    echo "cluster-link: peer is armed again, but the cross-boot budget for this halt's cause is spent (logged above); NOT re-arming — an automatic clear that keeps re-arming into the same failure is exactly what that budget exists to stop" >&2
    return 0
  fi
  echo "cluster-link: peer transitioned to armed ($now_key); clearing this host's halt marker so the pair re-arms together — the latch is kept, so the next tick re-verifies every precondition and re-halts if the cause still holds"
  rm -f "$halt_file"
  return 0
}
