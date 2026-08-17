# shellcheck shell=bash
# jaccl failure-stage classifier — SHARED by every consumer that bills or
# gates against the RDMA protection-domain budget.
#
# Split into its own file (rather than living in cluster-link-guards.sh, its
# original home) because it has TWO consumers on TWO different privilege
# layers: fast_fail_standdown (watcher-only, cluster-link-guards.sh) and
# pd_debt_settle_counter (watcher AND cluster-join AND cluster-detach,
# cluster-pd-settle.sh). cluster-join and cluster-detach never carry
# cluster-link-guards.sh — join and detach have no business starting or
# gating a rank, so they get none of its rank-start preconditions — but both
# call pd_debt_settle_counter, and shellcheck's SC2329 fails a build the
# moment a function is shipped into a script that cannot reach it. This file
# is therefore the smallest thing all three concatenations can share, per the
# per-consumer layering rule in ./cluster-script-layers.nix.
#
# Concatenated ahead of cluster-pd-settle.sh (and, in the watcher, ahead of
# cluster-link-guards.sh too) in every layer that uses it.

# STAGE A (TCP bootstrap) vs STAGE B (RDMA queue-pair bring-up) — jaccl brings a
# cluster up in these two distinct stages, confirmed from libjaccl.dylib's own
# error strings. Stage A: "Connection attempt ", "Couldn't connect (error: N)",
# "Couldn't listen", "Accept failed". Stage B, reached only once A succeeds:
# "...RTR failed with errno N", "...RTS failed with errno N", ibv_query_gid.
# ibv_alloc_pd — the call that actually consumes a protection domain — lives in
# Stage B, so a Stage-A-only death structurally could not have leaked one.
#
# Classifies from the rank's own stderr, SLICED FROM AN OFFSET rather than
# tailed by line count. launchd's StandardErrorPath appends across every rank
# restart, so a bare tail always includes whatever the PREVIOUS attempt wrote —
# and a bare-line-count tail can still be entirely stale prior-attempt output
# if this attempt died leaving no stderr of its own (e.g. SIGKILLed mid-init,
# after ibv_alloc_pd already ran). Reading that stale Stage-A tail as THIS
# attempt's evidence would free a death that may have actually reached Stage B
# — exactly the unclassifiable-treated-as-free hole this function exists to
# close, just entered through staleness instead of pattern-matching. Each
# caller writes its own byte-size marker as $2 right before the window it
# wants classified begins (a single kickstart for fast_fail_standdown, an
# entire unsettled run of them for pd_debt_settle_counter); this reads only
# what was appended since.
#
# ONLY TERMINAL failure strings count as Stage A ("Couldn't connect (error:",
# "Couldn't listen", "Accept failed") — never the bare "Connection attempt "
# retry line. A rank that got PAST Stage A and died silently in Stage B before
# printing an RTR/RTS line still has its own "Connection attempt" lines in the
# appended region (from its own successful bootstrap); matching on those alone
# would misclassify it as Stage-A-only. No terminal string from either stage
# present classifies "unknown", not "stage-a".
#
# FAILS CLOSED: no log path, an unreadable log, an offset marker path that was
# GIVEN but is missing or unreadable (a caller that names a marker meant one to
# be there — its absence is suspicious, not "read from the start"), an offset
# at or past the log's current size (nothing new appended — the stale-evidence
# case above), or a slice matching neither stage's terminal strings all
# classify "unknown" — every caller must treat that the same as a confirmed
# Stage-B failure, because an unclassifiable failure being treated as free is
# exactly how a domain leak goes unbounded. A caller that passes NO marker
# path at all ($2 empty) gets offset 0 — "classify the whole log" — which is a
# deliberate, different default for a caller that never scopes the window.
#
# $1 rank stderr log path, $2 byte-offset marker file (baseline captured by
# the caller at the start of the window being classified; empty = classify
# from the start of the log). Prints "stage-a" | "stage-b" | "unknown".
rank_failure_stage() {
  local log="$1" offset_file="$2" offset size appended
  if [ -z "$log" ] || [ ! -r "$log" ]; then
    echo unknown
    return
  fi
  offset=0
  if [ -n "$offset_file" ]; then
    if [ ! -r "$offset_file" ]; then
      echo unknown
      return
    fi
    # wc -c right-justifies with leading spaces on macOS (BSD) but not on
    # Linux (GNU) — stripped here rather than relied on at every writer, so a
    # marker written on either platform reads back the same way.
    offset="$(cat "$offset_file" 2> /dev/null || echo 0)"
    offset="${offset//[[:space:]]/}"
    case "$offset" in
      '' | *[!0-9]*) offset=0 ;;
    esac
  fi
  size="$(wc -c < "$log" 2> /dev/null || echo 0)"
  size="${size//[[:space:]]/}"
  case "$size" in
    '' | *[!0-9]*) size=0 ;;
  esac
  if [ "$offset" -ge "$size" ]; then
    echo unknown
    return
  fi
  appended="$(tail -c "+$((offset + 1))" "$log" 2> /dev/null || true)"
  if printf '%s\n' "$appended" | grep -qE "RTR failed with errno|RTS failed with errno|ibv_query_gid"; then
    echo stage-b
    return
  fi
  if printf '%s\n' "$appended" | grep -qE "Couldn't connect \(error:|Couldn't listen|Accept failed"; then
    echo stage-a
    return
  fi
  echo unknown
}
