#!/usr/bin/env bash
# Behavioural tests for the Codex quota push: codex-quota-metrics (the reader)
# and agent-quota-push (the generic pusher). Nothing is posted. A stub curl
# records each call, and a stub hostname fixes the host label, so the
# exposition is compared exactly.
#
# (a) THE MAPPING. A 300-minute and a 10080-minute window, both resetting in the
#     future, yield exactly the expected exposition plus the heartbeat, and one
#     POST carries it with the token file named in argv and the token absent.
# (b) NO READING, NO PUSH. A missing sessions dir, an empty one, and a record
#     with a malformed window each give no stdout, a non-zero exit and no POST.
#     A failing reader beside a good one blocks the push too.
# (c) PAST WINDOWS ARE OMITTED. A window whose reset has passed emits nothing.
# (d) OTHER WINDOWS ARE SKIPPED. A window_minutes other than 300 or 10080 emits nothing.
# (e) A FAILED POST EXITS NON-ZERO.
set -o errexit -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent_dir="$repo_root/modules/agent-hooks"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail=0
check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "  ok   $label"
  else
    echo "  FAIL $label"
    echo "       want: $want"
    echo "       got:  $got"
    fail=1
  fi
}
same_file() {  # label, want file, got file
  if diff -u "$2" "$3" > "$work/diff"; then
    echo "  ok   $1"
  else
    echo "  FAIL $1"
    cat "$work/diff"
    fail=1
  fi
}
has() {  # file, text -> yes|no
  if grep -qF -- "$2" "$1"; then echo yes; else echo no; fi
}

bin="$work/bin"
curl_dir="$work/curl"
codex_home="$work/codex-home"
sessions="$codex_home/sessions"
token="stub-token-value"
mkdir -p "$bin"
printf '%s\n' "$token" > "$work/token"

# The reader as default.nix builds it: the shared selection, then its body.
{
  printf '#!%s\nset -o errexit -o nounset -o pipefail\n' "$BASH"
  cat "$agent_dir/codex-rollouts.sh" "$agent_dir/codex-quota-metrics.sh"
} > "$bin/codex-quota-metrics"
chmod +x "$bin/codex-quota-metrics"

printf '#!/bin/sh\necho "failing-reader: no reading" >&2\nexit 1\n' > "$bin/failing-reader"
printf '#!/bin/sh\necho testhost\n' > "$bin/hostname"
chmod +x "$bin/failing-reader" "$bin/hostname"

cat > "$bin/curl" <<'SH'
#!/bin/sh
# Stub curl: records the call and the body on stdin, fails when CURL_STUB_FAIL is set.
dir="$CURL_STUB_DIR"
n="$(cat "$dir/count" 2>/dev/null || echo 0)"
echo $((n + 1)) > "$dir/count"
printf '%s\n' "$*" > "$dir/argv"
cat > "$dir/body"
if [ -n "${CURL_STUB_FAIL:-}" ]; then
  echo "curl: (22) The requested URL returned error: 401" >&2
  exit 22
fi
SH
chmod +x "$bin/curl"

# Fixtures. The reading timestamp is the record's own time; the reset times are
# far in the future and long past.
ts="2026-11-11T08:00:00.000Z"
reading=1794384000   # 2026-11-11T08:00:00Z
future=4102444800    # 2100-01-01T00:00:00Z
past=1000000000      # 2001-09-09T01:46:40Z

rollout() {  # record timestamp, primary JSON, secondary JSON
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":%s,"secondary":%s}}}\n' "$1" "$2" "$3"
}
five_hour() {  # used_percent, resets_at
  printf '{"used_percent":%s,"window_minutes":300,"resets_at":%s}' "$1" "$2"
}
weekly() {  # used_percent, resets_at
  printf '{"used_percent":%s,"window_minutes":10080,"resets_at":%s}' "$1" "$2"
}

exp_both="$work/expected-both"
cat > "$exp_both" <<EOF
agent_quota_used_percent{executor="codex",window="5h",source="rollout_record",host="testhost"} 12.5
agent_quota_window_seconds{executor="codex",window="5h",source="rollout_record",host="testhost"} 18000
agent_quota_reset_timestamp_seconds{executor="codex",window="5h",source="rollout_record",host="testhost"} 4102444800
agent_quota_reading_timestamp_seconds{executor="codex",window="5h",source="rollout_record",host="testhost"} ${reading}
agent_quota_used_percent{executor="codex",window="weekly",source="rollout_record",host="testhost"} 40
agent_quota_window_seconds{executor="codex",window="weekly",source="rollout_record",host="testhost"} 604800
agent_quota_reset_timestamp_seconds{executor="codex",window="weekly",source="rollout_record",host="testhost"} 4102444800
agent_quota_reading_timestamp_seconds{executor="codex",window="weekly",source="rollout_record",host="testhost"} ${reading}
EOF
exp_weekly="$work/expected-weekly"
tail -n 4 "$exp_both" > "$exp_weekly"

reset_case() {
  rm -rf "$sessions" "$curl_dir"
  mkdir -p "$sessions" "$curl_dir"
}
curl_calls() { cat "$curl_dir/count" 2>/dev/null || echo 0; }

run_reader() {  # sets rrc; stdout and stderr go to $work/rout and $work/rerr
  set +o errexit
  env PATH="$bin:$PATH" CODEX_HOME="$codex_home" "$bin/codex-quota-metrics" > "$work/rout" 2> "$work/rerr"
  rrc=$?
  set -o errexit
}
run_pusher() {  # usage: run_pusher READER...; sets prc; stdout and stderr go to $work/pout and $work/perr
  set +o errexit
  env PATH="$bin:$PATH" CODEX_HOME="$codex_home" CURL_STUB_DIR="$curl_dir" \
    CURL_STUB_FAIL="${CURL_STUB_FAIL:-}" \
    AGENT_QUOTA_WRITE_URL="http://push.example.test/api/v1/import/prometheus" \
    AGENT_QUOTA_WRITE_TOKEN_FILE="$work/token" \
    bash "$agent_dir/quota-push.sh" "$@" > "$work/pout" 2> "$work/perr"
  prc=$?
  set -o errexit
}
expect_no_push() {  # label
  run_reader
  check "$1: reader exits 1" 1 "$rrc"
  check "$1: reader prints nothing" "" "$(cat "$work/rout")"
  run_pusher "$bin/codex-quota-metrics"
  check "$1: pusher exits 1" 1 "$prc"
  check "$1: no POST made" 0 "$(curl_calls)"
}
heartbeat_ok() {  # before, after -> yes|no; checks the heartbeat line in the POST body
  local line value
  line="$(grep '^agent_quota_probe_last_success_timestamp_seconds{executor="codex",host="testhost"} ' "$curl_dir/body" || true)"
  value="${line##* }"
  if [ -n "$line" ] && [ "$value" -ge "$1" ] && [ "$value" -le "$2" ]; then echo yes; else echo no; fi
}

echo "(a) mapping: 5h and weekly windows, both resetting in the future"
reset_case
rollout "$ts" "$(five_hour 12.5 $future)" "$(weekly 40 $future)" > "$sessions/rollout-a.jsonl"
before="$(date +%s)"
run_pusher "$bin/codex-quota-metrics"
after="$(date +%s)"
check "pusher exits 0" 0 "$prc"
check "one POST" 1 "$(curl_calls)"
check "pusher logs one line" "agent-quota-push: pushed 9 series" "$(cat "$work/pout")"
grep -v '^agent_quota_probe' "$curl_dir/body" > "$work/got-a"
same_file "exact exposition lines" "$exp_both" "$work/got-a"
check "heartbeat is present and within this run" yes "$(heartbeat_ok "$before" "$after")"
check "argv names the token file" yes "$(has "$curl_dir/argv" "token@$work/token")"
check "argv never holds the token" no "$(has "$curl_dir/argv" "$token")"
check "argv carries --fail and the 20 s timeout" yes "$(has "$curl_dir/argv" "--fail --silent --show-error --max-time 20")"

echo "(b) no reading: nothing pushed"
reset_case
rm -rf "$sessions"
expect_no_push "no sessions dir"
reset_case
expect_no_push "empty sessions dir"
reset_case
rollout "$ts" "$(five_hour 12.5 $future)" '{"used_percent":"oops","window_minutes":10080,"resets_at":4102444800}' > "$sessions/rollout-b.jsonl"
expect_no_push "malformed weekly window"
reset_case
rollout "$ts" "$(five_hour 12.5 $future)" "$(weekly 40 $future)" > "$sessions/rollout-b.jsonl"
run_pusher "$bin/failing-reader" "$bin/codex-quota-metrics"
check "a failing reader blocks the push: exit 1" 1 "$prc"
check "a failing reader blocks the push: no POST" 0 "$(curl_calls)"

echo "(c) a window whose reset has passed is omitted"
reset_case
rollout "$ts" "$(five_hour 96 $past)" "$(weekly 40 $future)" > "$sessions/rollout-c.jsonl"
run_pusher "$bin/codex-quota-metrics"
check "pusher exits 0" 0 "$prc"
grep -v '^agent_quota_probe' "$curl_dir/body" > "$work/got-c"
same_file "only the weekly lines remain" "$exp_weekly" "$work/got-c"
check "pusher logs 5 series" "agent-quota-push: pushed 5 series" "$(cat "$work/pout")"

echo "(d) a window other than 300 or 10080 minutes is skipped"
reset_case
rollout "$ts" '{"used_percent":12.5,"window_minutes":60,"resets_at":4102444800}' "$(weekly 40 $future)" > "$sessions/rollout-d.jsonl"
run_pusher "$bin/codex-quota-metrics"
check "pusher exits 0" 0 "$prc"
grep -v '^agent_quota_probe' "$curl_dir/body" > "$work/got-d"
same_file "only the weekly lines remain" "$exp_weekly" "$work/got-d"

echo "(e) a failed POST exits non-zero"
reset_case
rollout "$ts" "$(five_hour 12.5 $future)" "$(weekly 40 $future)" > "$sessions/rollout-e.jsonl"
export CURL_STUB_FAIL=1
run_pusher "$bin/codex-quota-metrics"
unset CURL_STUB_FAIL
check "pusher exits 1" 1 "$prc"
check "POST was attempted" 1 "$(curl_calls)"
check "stderr names the failed push" yes "$(has "$work/perr" "push failed")"

if [ "$fail" -ne 0 ]; then
  echo "FAILED"
  exit 1
fi
echo "all codex-quota-push tests passed"
