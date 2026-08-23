#!/usr/bin/env bash
# THE CHECK THAT FAILS IF THE QUIESCE SNAPSHOT READ CAN KILL THE TICK.
#
# quiesce_normal_serving (cluster-link-helpers.sh) snapshots in-flight requests
# from the proxy's SSE stream: `curl --no-buffer .../api/events | grep -m1
# '^data:'`. The stream stays open by design, so grep -m1 closes the pipe after
# the first match and curl dies on the write error. Under the watcher's
# errexit+pipefail that nonzero pipeline rc killed the whole tick BEFORE the
# snapshot echo — the coordinator held for the rank-start boundary and then
# silently died, every tick, and the cluster never formed. This pins that the
# assignment tolerates the pipeline rc: a streaming proxy must yield the
# snapshot line and an unreachable proxy the "none" branch, and BOTH must reach
# the unload that follows.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL — quiesce_normal_serving, sourced from the shipped layer and run under
#          the exact flags the watcher sets (errexit, nounset, pipefail).
#   STUB — curl, as a generated executable on PATH (the function calls a bare
#          `curl`): in stream mode it prints one data: line then keeps writing
#          like a held-open SSE stream, so it takes the same broken-pipe death
#          the real curl takes when grep -m1 hangs up; the unload POST is
#          logged and succeeds.
#
# Usage:
#   HELPERS=... bash test-quiesce-snapshot.sh
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

helpers="${HELPERS:?set HELPERS to cluster-link-helpers.sh}"

# `#!/usr/bin/env bash` does not resolve in a Linux nix build sandbox; $BASH is
# the running interpreter's own absolute path (same fix as
# tests/test-serving-restore.sh).
mkdir -p "$tmp/bin"
{
  printf '#!%s\n' "$BASH"
  cat << 'FAKE'
set -e
for a in "$@"; do case "$a" in
  */api/models/unload) echo unload >> "$FAKE_DIR/curl-log"; exit 0 ;;
  */api/events)
    [ "${FAKE_EVENTS_UP:-1}" = 1 ] || exit 7   # connection refused shape
    printf 'data: {"requests":[{"id":"r1"}]}\n'
    # The stream stays open: keep writing until the reader hangs up, which is
    # what kills the left side of the pipe with a broken-pipe rc — the exact
    # death the real curl takes. Bounded so a leak cannot hang the suite.
    i=0
    while [ "$i" -lt 100 ]; do
      printf ': keepalive\n'
      sleep 0.05
      i=$((i + 1))
    done
    exit 0 ;;
esac; done
exit 0
FAKE
} > "$tmp/bin/curl"
chmod +x "$tmp/bin/curl"
export FAKE_DIR="$tmp"

# The function under the watcher's own flags, in its own process so a death
# there cannot take the suite down with it.
cat > "$tmp/driver" << DRIVER
#!$BASH
set -o errexit -o nounset -o pipefail
PATH="$tmp/bin:\$PATH"
# shellcheck disable=SC1090
source '$helpers'
CLUSTER_ROLE=coordinator
CLUSTER_NORMAL_PROXY=http://127.0.0.1:19
quiesce_normal_serving
echo SURVIVED
DRIVER
chmod +x "$tmp/driver"

fail=0
check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "  ok   $label -> $got"
  else
    echo "  FAIL $label -> got '$got', want '$want'"
    fail=1
  fi
}
contains() {
  local label="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) echo "  ok   $label" ;;
    *)
      echo "  FAIL $label -> '$needle' not in: $hay"
      fail=1
      ;;
  esac
}

echo "1. a streaming /api/events must not kill the tick:"
rm -f "$tmp/curl-log"
out="$(FAKE_EVENTS_UP=1 "$tmp/driver" 2>&1)" && rc=0 || rc=$?
check "the tick survives the closed-pipe curl death" 0 "$rc"
contains "and still echoes the snapshot" "quiesce in-flight snapshot:" "$out"
contains "with the in-flight request id" "r1" "$out"
contains "and reaches the unload after it" "quiesce unload request completed" "$out"
check "the unload was actually requested" unload "$(cat "$tmp/curl-log" 2> /dev/null || echo missing)"

echo "2. an unreachable proxy must not kill the tick either:"
rm -f "$tmp/curl-log"
out="$(FAKE_EVENTS_UP=0 "$tmp/driver" 2>&1)" && rc=0 || rc=$?
check "the tick survives an unreachable /api/events" 0 "$rc"
contains "and says so through the handled branch" "none (or /api/events unreachable)" "$out"
contains "and still reaches the unload" "quiesce unload request completed" "$out"

exit "$fail"
