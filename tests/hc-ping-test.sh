# shellcheck shell=bash
# hc_ping() deadman contract test.
#
# The watchdog pings every url in the healthcheck file, one per line, so a
# second monitor added to the file is reached without a code change. Blank
# lines and #-comments are skipped, a missing file is a no-op, and one
# unreachable monitor does not stop the rest from being pinged.
#
# mlx-watchdog.sh runs its main body on load, so only the hc_ping function is
# extracted from it (definition through its closing brace) and evaluated here.
#
# Standalone-runnable: needs bash and coreutils, and a `curl` on PATH that
# appends its last argument to $FAKE_PING_LOG and exits 1 for a url containing
# "down".
#
# Usage: WATCHDOG=/path/to/mlx-watchdog.sh bash hc-ping-test.sh

set -o errexit
set -o nounset
set -o pipefail

out="${out:-}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export FAKE_PING_LOG="$work/pings"
: > "$FAKE_PING_LOG"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

healthcheck_url_file="$work/healthcheck-url"
eval "$(sed -n '/^hc_ping() {$/,/^}$/p' "$WATCHDOG")"
declare -F hc_ping > /dev/null || fail "hc_ping not extracted from $WATCHDOG"

# Missing file: no-op, no pings.
hc_ping
[[ ! -s "$FAKE_PING_LOG" ]] || fail "missing url file produced pings"

# Two monitors, a comment, a blank line, trailing whitespace, one unreachable.
printf '# first monitor\nhttps://one.example/ping/a  \n\nhttps://down.example/ping/b\nhttps://two.example/ping/c\n' > "$healthcheck_url_file"
hc_ping
expected=$'https://one.example/ping/a\nhttps://down.example/ping/b\nhttps://two.example/ping/c'
[[ "$(<"$FAKE_PING_LOG")" == "$expected" ]] || fail "pinged: $(<"$FAKE_PING_LOG")"

# A single url without a trailing newline is still pinged.
: > "$FAKE_PING_LOG"
printf 'https://one.example/ping/a' > "$healthcheck_url_file"
hc_ping
[[ "$(<"$FAKE_PING_LOG")" == "https://one.example/ping/a" ]] || fail "no-newline url skipped"

echo "hc_ping: every listed monitor pinged"
[[ -z "$out" ]] || : > "$out"
