# shellcheck shell=bash
# alert() Slack contract test.
#
# Both failure modes covered here are SILENT in production — malformed JSON is
# rejected by Slack as invalid_payload, and a non-200 used to vanish under
# `|| true` — so this is the check that fails if either regresses.
#
# Sources cluster-link-helpers.sh, which is function-definitions-only and so can
# be sourced without running the watcher. mlx-watchdog.sh carries an identical
# alert(); keep the two in step.
#
# Standalone-runnable: needs bash, jq, coreutils, and a `curl` on PATH that
# records --data-binary into $FAKE_PAYLOAD_FILE and prints "<body>\n<code>"
# with the code read from $FAKE_CODE_FILE.
#
# Usage: HELPERS=/path/to/cluster-link-helpers.sh bash alert-payload-test.sh

set -o errexit
set -o nounset
set -o pipefail

# Supplied by the nix builder when this runs as the check body; empty for a
# standalone run. Declared here so it is an assigned variable either way.
out="${out:-}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export FAKE_PAYLOAD_FILE="$work/payload"
export FAKE_CODE_FILE="$work/code"
export CLUSTER_ALERT_URL_FILE="$work/webhook"
printf 'https://hooks.example/T/B/X' > "$CLUSTER_ALERT_URL_FILE"
printf '200' > "$FAKE_CODE_FILE"

fail() {
  echo "FAIL: $1" >&2
  shift || true
  [ "$#" -eq 0 ] || printf '%s\n' "$@" >&2
  exit 1
}

# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to the path of cluster-link-helpers.sh}"

# Free text carrying every character class that breaks hand-built JSON.
hostile='host: rank "wedged" after 3 starts
model=some-org/Some-Model-4.7 path=C:\tmp 100% <&>'

alert "$hostile" 2> "$work/err1"

jq -e . "$FAKE_PAYLOAD_FILE" > /dev/null 2>&1 ||
  fail "payload is not valid JSON" "$(cat "$FAKE_PAYLOAD_FILE")"

got="$(jq -r .text "$FAKE_PAYLOAD_FILE")"

case "$got" in
  *'rank "wedged" after 3 starts'*) ;;
  *) fail "embedded quotes mangled" "$got" ;;
esac

case "$got" in
  *'some-org/Some-Model-4.7'*) ;;
  *) fail "slashes mangled" "$got" ;;
esac

case "$got" in
  *'C:\tmp'*) ;;
  *) fail "backslash mangled" "$got" ;;
esac

# Severity/source prefix: a page must be distinguishable from chatter at a glance.
case "$got" in
  *rotating_light*) ;;
  *) fail "severity/source prefix missing" "$got" ;;
esac

[ "$(printf '%s' "$got" | wc -l)" -ge 1 ] || fail "embedded newline lost" "$got"

[ ! -s "$work/err1" ] || fail "a healthy 200 must log nothing" "$(cat "$work/err1")"

# A rejected page must be logged, never fatal.
printf '500' > "$FAKE_CODE_FILE"
alert "second page" 2> "$work/err2" || fail "alert must never return nonzero"
grep -q 'alert POST failed http=500' "$work/err2" ||
  fail "a rejected page must be logged, not swallowed" "$(cat "$work/err2")"
grep -q 'slack-said-no' "$work/err2" ||
  fail "the response body carries Slack's reason and must be logged" "$(cat "$work/err2")"

# Unconfigured is not broken: a missing url file stays a silent no-op.
rm -f "$CLUSTER_ALERT_URL_FILE" "$FAKE_PAYLOAD_FILE"
alert "third page" 2> "$work/err3" || fail "missing url file must no-op"
[ ! -e "$FAKE_PAYLOAD_FILE" ] || fail "posted with no url file present"

echo "alert() Slack contract OK"

# Doubles as the body of the nix check. Gate on NIX_BUILD_TOP, not on $out:
# `out` is a common variable name and leaks in from ordinary shells, which made
# a standalone run try to touch someone else's path. NIX_BUILD_TOP is set only
# inside a nix builder, where $out is guaranteed.
if [ -n "${NIX_BUILD_TOP:-}" ]; then
  touch "$out"
fi
