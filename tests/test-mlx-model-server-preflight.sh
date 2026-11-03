#!/usr/bin/env bash
# Regression guard for the static-resident preflight cluster guard.
#
# Runs the real preflight against a fake HOME and a stand-in server. The
# preflight refuses (exit 75, server not started) when link-state is "up" and
# peer-state.json reports armed true. It also refuses when a state file exists
# but cannot be read or parsed. A missing state file means not clustered.
set -o errexit -o nounset -o pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
preflight="$root/modules/mlx/scripts/mlx-model-server-preflight.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

server="$work/fake-server"
printf '#!/usr/bin/env bash\necho SERVER-STARTED\n' > "$server"
chmod +x "$server"

failures=0

# run_case <name> <link-state|-> <peer-state|-> <expected rc> <expected started 1|0>
run_case() {
  local name="$1" link="$2" peer="$3" want_rc="$4" want_started="$5"
  local home="$work/$name"
  local dir="$home/Library/Application Support/mlx-cluster"
  mkdir -p "$dir"
  # DIR makes link-state a directory, so reading it fails.
  if [ "$link" = DIR ]; then mkdir "$dir/link-state"
  elif [ "$link" != - ]; then printf '%s\n' "$link" > "$dir/link-state"; fi
  if [ "$peer" != - ]; then printf '%s\n' "$peer" > "$dir/peer-state.json"; fi

  local out rc
  set +o errexit
  out=$(HOME="$home" PATH="$PATH" bash "$preflight" "$server" serve 2>"$work/$name.err")
  rc=$?
  set -o errexit

  local started=0
  if [[ "$out" == *SERVER-STARTED* ]]; then started=1; fi

  if [ "$rc" != "$want_rc" ] || [ "$started" != "$want_started" ]; then
    echo "FAIL $name: rc=$rc (want $want_rc) started=$started (want $want_started)" >&2
    cat "$work/$name.err" >&2
    failures=$((failures + 1))
  else
    echo "ok   $name: rc=$rc started=$started"
  fi
}

run_case refuse-up-armed up '{"armed": true}' 75 0
run_case start-down-armed down '{"armed": true}' 0 1
run_case start-up-disarmed up '{"armed": false}' 0 1
run_case start-link-missing - '{"armed": true}' 0 1
run_case start-peer-missing up - 0 1
run_case refuse-peer-malformed-link-up up '{not json' 75 0
run_case refuse-peer-malformed-link-down down '{not json' 75 0
run_case refuse-link-unreadable DIR '{"armed": true}' 75 0
run_case refuse-peer-empty up '' 75 0
run_case refuse-peer-two-documents up '{"armed": true}{"armed": false}' 75 0
run_case refuse-peer-armed-not-boolean up '{"armed": "true"}' 75 0
run_case start-peer-no-armed-key up '{}' 0 1

if ! grep -q 'refuse reason=clustered' "$work/refuse-up-armed.err"; then
  echo "FAIL refuse-up-armed: refusal was not logged with its reason" >&2
  failures=$((failures + 1))
fi
if ! grep -q 'refuse reason=peer-state-unreadable' "$work/refuse-peer-malformed-link-up.err"; then
  echo "FAIL refuse-peer-malformed-link-up: refusal reason was not logged" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures preflight cluster-guard case(s) failed" >&2
  exit 1
fi
