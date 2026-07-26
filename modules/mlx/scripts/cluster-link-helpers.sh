# shellcheck shell=bash
# Cluster link watcher — serving-state helpers.
#
# Concatenated ahead of cluster-link-watcher.sh by the module (split out for
# the per-file size cap). Function definitions only — the CLUSTER_* env the
# bodies read is resolved at call time. Every function here is idempotent and
# safe to re-run, which is what lets the watcher retry an incomplete teardown
# instead of consuming the link-state edge on a swallowed error.

# Page once via Slack incoming webhook, only if the untracked url file exists.
# Slack needs application/json {"text": ...} — a raw ntfy-style body is rejected
# as invalid_payload, and it has no Priority/Title headers, so severity and
# source are folded into the text. Callers already prefix the hostname.
# Mirrors alert() in mlx-watchdog.sh; keep the two in step.
#
# $1 = message text, $2 = headline naming the condition, so a page is
# identifiable at a glance. Several conditions share this function (PD-guard
# halt, wedged rank, no token progress, worker rank down, rejected manual
# clear), and the Slack markup is applied HERE from the plain headline — callers
# pass words, never formatting.
#
# A PAGE THAT REACHES NOBODY MUST STILL REACH THE LOG. On 2026-07-24 the single
# alert of the incident died as `alert POST failed http=000 body=curl: (7)
# Failed to connect` and the message content — the only record of WHY the rank
# halted — went nowhere at all. So every non-delivery path below logs the FULL
# text, not just a status code, and appends it to an undelivered-pages file:
# a silent pager must never also mean a silent log.
alert() {
  local text="$1" headline="${2:-mlx-cluster alert}"
  local payload resp code body undelivered
  undelivered="$(dirname "${CLUSTER_STATE_FILE:-/dev/null}")/alerts-undelivered.log"
  if [ ! -f "${CLUSTER_ALERT_URL_FILE:-}" ]; then
    # Unconfigured is not broken (a missing url file is a valid "no pager"), but
    # it is not silent either: the page's content is the incident record.
    echo "cluster-link: WARN no alert URL file (${CLUSTER_ALERT_URL_FILE:-unset}); page NOT sent: $headline — $text" >&2
    alert_record "$undelivered" "no-url-file" "$headline" "$text"
    return 0
  fi
  # jq, never string interpolation: "$1" is free text carrying quotes, newlines
  # and model ids with slashes. Hand-built JSON breaks on all three and Slack
  # rejects it — silently, which is the failure mode being fixed here.
  if ! payload="$(jq -n --arg text ":rotating_light: *$headline* — $text" '{text: $text}')"; then
    echo "cluster-link: WARN alert encode FAILED; page NOT sent: $headline — $text" >&2
    alert_record "$undelivered" "encode-failed" "$headline" "$text"
    return 0
  fi
  # No -f: it suppresses the response body, and Slack puts the reason there.
  # Never fatal — an alerter must not take down what it monitors — but ALWAYS
  # logged, so a broken pager is discoverable instead of silently swallowed.
  resp="$(curl -sS -m 10 -X POST -H 'Content-Type: application/json' \
    --data-binary "$payload" -w $'\n%{http_code}' \
    "$(cat "$CLUSTER_ALERT_URL_FILE")" 2>&1)" || true
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [ "$code" != "200" ]; then
    echo "cluster-link: WARN alert POST failed http=${code:-none} body=${body:0:200}" >&2
    echo "cluster-link: WARN undelivered page: $headline — $text" >&2
    alert_record "$undelivered" "http=${code:-none}" "$headline" "$text"
  fi
}

# Append an undelivered page to a local file, so the record survives log
# rotation of the watcher's stderr. Best-effort by design: an alerter that dies
# because it could not write its own audit trail is worse than one that cannot.
alert_record() {
  local file="$1" why="$2" headline="$3" text="$4"
  mkdir -p "$(dirname "$file")" 2> /dev/null || return 0
  printf '%s\tundelivered(%s)\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$why" "$headline" "$text" >> "$file" 2> /dev/null || true
}

# Halt the rank-start loop, recording WHY. The marker used to be a bare `touch`,
# so a later reader — human or agent — could see that kickstarts were halted but
# not what halted them, and the fastest way to "make progress" was to delete it.
#
# Lives here rather than in cluster-link-guards.sh because BOTH the watcher and
# the peer-liveness supervisor set this latch, and the cause is worth recording
# whichever one did it.
#
# $1 halt marker, $2 latch, $3 cause token, $4 free-text detail.
# Drop a halt that was recorded before the current boot.
#
# Every cause a halt can record is process or kernel state: exhausted RDMA
# protection domains, a wedged rank process, a precondition that was failing at
# the time. None of it survives a reboot — and the project's own doctrine is that
# PD exhaustion is reboot-only to clear. So a halt written before this boot is
# stale by construction.
#
# Without this, a cold boot can never form the cluster: the marker and its latch
# outlive the machine, the watcher takes the halted branch forever, and only a
# link cycle or a human clears it. That was masked for a long time because every
# test cleared the marker by hand first, which quietly made "unattended
# formation" untested.
#
# This is not a bypass. rank_start_preconditions_ok still runs before any start,
# so a cause that really does still hold re-halts on its own evidence. All this
# removes is a dead generation's verdict outliving the generation.
# Seconds since epoch at which this kernel booted, or empty if unavailable.
#
# Anchored on purpose. kern.boottime reads
#   { sec = 1785031601, usec = 233215 } Sat Jul 25 22:06:41 2026
# so an unanchored `.*sec = ` matches through "usec = " and captures the
# MICROSECONDS instead — a value so small that nothing ever looks older than it,
# which silently disables every check built on this.
current_boot_epoch() {
  sysctl -n kern.boottime 2> /dev/null | sed -n 's/^{ *sec *= *\([0-9]*\).*/\1/p'
}

halt_drop_if_pre_boot() {
  local halt_file="$1" latch_file="$2" kicks_file="$3" now_boot recorded
  now_boot="$(current_boot_epoch)"
  # Unknown boot time: leave the halt alone. Failing closed keeps the PD guard.
  [ -n "$now_boot" ] || return 0
  [ -e "$halt_file" ] || return 0
  # Field-exact, not a greedy regex: the detail text is operator-facing prose and
  # must never be able to spoof the field this decision reads.
  recorded="$(awk -F'\t' '{for (i = 1; i <= NF; i++) if ($i ~ /^boot=/) { sub(/^boot=/, "", $i); print $i; exit }}' "$halt_file" 2> /dev/null)"
  if [ "$recorded" != "$now_boot" ]; then
    echo "cluster-link: halt was recorded under boot '${recorded:-unknown}' but this is boot '$now_boot'; dropping it — a reboot clears every cause a halt can record, and keeping it would make cold-boot formation impossible"
    rm -f "$halt_file" "$latch_file" "$kicks_file"
  fi
  return 0
}

halt_write() {
  local halt_file="$1" latch_file="$2" cause="$3" detail="$4"
  # boot= is what makes the halt scoped to the machine's current life. Read back
  # by halt_drop_if_pre_boot: a halt from a previous boot cannot still be true,
  # because every cause recorded here is process or kernel state.
  printf '%s\tcause=%s\tboot=%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cause" "$(current_boot_epoch)" "$detail" > "$halt_file"
  # The latch outlives a manual `rm` of the marker and is cleared only by a real
  # link cycle, an accepted clear, or cluster-join. It is what makes the halt
  # more than a file someone can delete (see halt_clear_accepted).
  printf '%s\n' "$cause" > "$latch_file"
}

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

# Bring normal serving back. Returns nonzero if it could not, so the caller can
# decline to consume the link-state edge and retry on the next tick.
restore_normal_serving() {
  local uid
  uid="$(id -u)"
  if [ "$CLUSTER_ROLE" = "coordinator" ]; then
    # INC-17071: the warmup one-shot re-warms the preload list by POSTing to
    # llama-swap over loopback, so if the server agent is not loaded the
    # kickstart hits nothing and no-ops SILENTLY -- serving never comes back.
    # cluster-join boots that agent out, so any session that used it left the
    # unattended cable-yank path unable to restore. Bootstrap it first, the
    # same way cluster-detach does, so both paths converge.
    if [ -n "${CLUSTER_SERVER_LABEL:-}" ] &&
      ! launchctl print "gui/$uid/$CLUSTER_SERVER_LABEL" > /dev/null 2>&1; then
      if [ ! -f "${CLUSTER_SERVER_PLIST:-}" ]; then
        echo "cluster-link: WARN $CLUSTER_SERVER_LABEL not loaded and no plist to bootstrap" >&2
        return 1
      fi
      echo "cluster-link: standalone server agent not loaded; bootstrapping"
      if ! launchctl bootstrap "gui/$uid" "$CLUSTER_SERVER_PLIST" > /dev/null 2>&1; then
        echo "cluster-link: WARN failed to bootstrap $CLUSTER_SERVER_LABEL" >&2
        return 1
      fi
    fi
    # Re-warm the declared preload list through the existing warmup one-shot.
    launchctl kickstart -k "gui/$uid/$CLUSTER_WARMUP_LABEL" || true
  elif [ -n "${CLUSTER_RESTORE_CMD:-}" ]; then
    # cluster-restore keeps the labels it could not bootstrap and exits nonzero
    # precisely so a later tick retries them; propagate that.
    sh -c "$CLUSTER_RESTORE_CMD" || return 1
  fi
}
