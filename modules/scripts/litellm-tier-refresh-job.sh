#!/usr/bin/env bash
# Timer entry point for the subagent fallback-tier refresh.
#
# The refresh itself only rewrites a JSON file in a CHECKOUT. Nothing reaches
# the running proxy until someone rebuilds, and that ordering is deliberate:
# this job PROPOSES a re-ranking, a human converges it. A timer that silently
# repointed live subagent traffic at whatever model was cheapest this morning
# is the same class of failure as the pinned model it replaced — nobody would
# know the model changed until output quality did.
#
# So the job's real product is the log line. It says whether the selection
# moved, and if it did, a rebuild is owed.
set -euo pipefail

CANDIDATES="${1:?candidates path required}"
REFRESH="${2:?refresh script path required}"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '%s %s\n' "$(ts)" "$*"; }

# A missing checkout is the expected failure on a machine where the repo moved
# or was never cloned, and it must be loud. A job that exits 0 having done
# nothing is indistinguishable from one that ran and found no change — that
# ambiguity is what let a stale alias survive for days.
if [ ! -f "$CANDIDATES" ]; then
  log "FATAL: candidates file not found: $CANDIDATES"
  log "       Set programs.litellmLocal.tierRefresh.checkout to a working copy"
  log "       of this repo, or disable programs.litellmLocal.tierRefresh.enable."
  exit 1
fi

# The ordered list of upstream ids IS the selection. Prices move constantly and
# a price-only change is not something a human needs to act on; a change to
# which models serve traffic is.
selection() {
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("UNREADABLE:%s" % e); raise SystemExit
print("\n".join("%s=%s" % (m.get("name"), m.get("upstream")) for m in d.get("members", [])))
' "$1"
}

before=$(selection "$CANDIDATES")

log "refreshing $CANDIDATES"
if ! output=$("$REFRESH" "$CANDIDATES" 2>&1); then
  log "FAILED: refresh exited non-zero"
  printf '%s\n' "$output"
  exit 1
fi
printf '%s\n' "$output"

after=$(selection "$CANDIDATES")

if [ "$before" = "$after" ]; then
  log "selection unchanged"
  exit 0
fi

log "SELECTION CHANGED — a rebuild is required before this takes effect"
# diff exits 1 on difference, which is the expected path here, so it must not
# trip `set -e`.
diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
