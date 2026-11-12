#!/usr/bin/env bash
# Test body for the codex-quota check (lib/checks/lint.nix).
# Runs the quota probe against a stub Codex CLI and temporary session data.
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"
script="${SRC}/modules/agent-hooks/codex-quota.sh"

fail=0

expect_case() {
  local label="$1" mode="$2" stub_exit="$3" session_json="$4"
  local expected_status="$5" expected_output="$6" setup_fn="${7:-}"
  local exhausted_threshold="${8:-95}" low_threshold="${9:-90}"
  local case_dir bin codex_home home output status line_count
  local -a args=()

  if [ "$mode" = json ]; then
    args=(--json)
  fi

  case_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-quota.XXXXXX")"
  bin="$case_dir/bin"
  codex_home="$case_dir/codex-home"
  home="$case_dir/home"
  mkdir -p "$bin" "$codex_home/sessions" "$home" "$case_dir/empty"

  printf '#!/bin/sh\necho "codex-cli stub"\nexit %s\n' "$stub_exit" > "$bin/codex"
  chmod +x "$bin/codex"

  if [ -n "$session_json" ]; then
    printf '%s\n' "$session_json" > "$codex_home/sessions/rollout-test.jsonl"
  fi
  if [ -n "$setup_fn" ]; then "$setup_fn" "$codex_home/sessions"; fi

  set +e
  (
    cd "$case_dir/empty"
    PATH="$bin:$PATH" \
      CODEX_HOME="$codex_home" \
      HOME="$home" \
      CODEX_QUOTA_EXHAUSTED_THRESHOLD="$exhausted_threshold" \
      CODEX_QUOTA_LOW_THRESHOLD="$low_threshold" \
      bash "$script" "${args[@]}"
  ) > "$case_dir/stdout" 2> "$case_dir/stderr"
  status=$?
  set -e

  output="$(cat "$case_dir/stdout")"
  line_count="$(wc -l < "$case_dir/stdout" | tr -d ' ')"
  rm -rf "$case_dir"

  if [ "$status" -eq "$expected_status" ] && [ "$output" = "$expected_output" ] && [ "$line_count" -eq 1 ]; then
    echo "PASS ($label): exit $status and exact one-line output"
  else
    echo "FAIL ($label): expected exit $expected_status and one line '$expected_output'; got exit $status" >&2
    printf 'Output: %s\n' "$output" >&2
    fail=1
  fi
}

expect_missing_cli() {
  local case_dir output status bash_bin
  case_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-quota.XXXXXX")"
  bash_bin="$(command -v bash)"
  set +e
  output=$(PATH="$case_dir" CODEX_HOME="$case_dir/no-codex-home" HOME="$case_dir/home" "$bash_bin" "$script" 2>&1)
  status=$?
  set -e
  rm -rf "$case_dir"
  if [ "$status" -eq 1 ] && [[ "$output" == *"codex: command not found"* ]]; then
    echo "PASS (CLI missing from PATH): exit $status and actual launch reason is printed"
  else
    echo "FAIL (CLI missing from PATH): expected exit 1 and command-not-found reason; got exit $status" >&2
    printf 'Output: %s\n' "$output" >&2
    fail=1
  fi
}
session_available='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":10,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'
session_low='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":90,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'
session_exhausted='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":95,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'
session_threshold_low='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":80,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'
session_threshold_exhausted='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":90,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'
session_reset='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":100,"resets_at":1},"secondary":{"used_percent":96,"resets_at":1}}}}'
session_malformed='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":'

record_stale='{"timestamp":"2026-11-05T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":10,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'
record_fresh='{"timestamp":"2026-11-08T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":96,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'

# The file holding the stale record is written second, so it carries the newer
# mtime; the probe must still report the greatest timestamp (96, exhausted).
write_racy_sessions() {
  local sessions_dir="$1"
  printf '%s\n' "$record_fresh" > "$sessions_dir/rollout-fresh.jsonl"
  sleep 2
  printf '%s\n' "$record_stale" > "$sessions_dir/rollout-stale.jsonl"
}

expect_case "CLI cannot run (legacy)" text 127 "" 1 "codex-quota: unavailable (the codex CLI does not run)"
expect_case "CLI cannot run (JSON unknown)" json 127 "" 2 '{"state":"unknown","primary":null,"secondary":null}'
expect_missing_cli
expect_case "no record (legacy)" text 0 "" 0 "codex-quota: available (no codex rate_limits record in 8 days)"
expect_case "no record (JSON unknown)" json 0 "" 2 '{"state":"unknown","primary":null,"secondary":null}'
expect_case "unparsable record (JSON unknown)" json 0 "$session_malformed" 2 '{"state":"unknown","primary":null,"secondary":null}'
expect_case "unparsable record (legacy)" text 0 "$session_malformed" 0 "codex-quota: available (no codex rate_limits record in 8 days)"

expect_case "available (JSON)" json 0 "$session_available" 0 '{"state":"available","primary":{"used_percent":10,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}'
expect_case "low boundary (JSON)" json 0 "$session_low" 0 '{"state":"low","primary":{"used_percent":90,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}'
expect_case "exhausted boundary (JSON)" json 0 "$session_exhausted" 1 '{"state":"exhausted","primary":{"used_percent":95,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}'

expect_case "available (legacy exact output)" text 0 "$session_available" 0 'codex-quota: available {"p":10,"s":10}'
expect_case "low remains available (legacy)" text 0 "$session_low" 0 'codex-quota: available {"p":90,"s":10}'
expect_case "exhausted boundary (legacy exact output)" text 0 "$session_exhausted" 1 'codex-quota: exhausted {"p":95,"s":10,"resets_at":9999999999}'

# The declared environment parameters drive both thresholds; defaults above
# cover the module defaults of 90 (low) and 95 (exhausted).
expect_case "custom low boundary (JSON)" json 0 "$session_threshold_low" 0 '{"state":"low","primary":{"used_percent":80,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}' "" 90 80
expect_case "custom exhausted boundary (JSON)" json 0 "$session_threshold_exhausted" 1 '{"state":"exhausted","primary":{"used_percent":90,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}' "" 90 80
expect_case "custom exhausted boundary (legacy)" text 0 "$session_threshold_exhausted" 1 'codex-quota: exhausted {"p":90,"s":10,"resets_at":9999999999}' "" 90 80

expect_case "reset-passed windows (JSON)" json 0 "$session_reset" 0 '{"state":"available","primary":{"used_percent":100,"resets_at":1},"secondary":{"used_percent":96,"resets_at":1}}'
expect_case "reset-passed windows (legacy)" text 0 "$session_reset" 0 'codex-quota: available {"p":100,"s":96}'
expect_case "newest timestamp wins over newest mtime" text 0 "" 1 'codex-quota: exhausted {"p":96,"s":10,"resets_at":9999999999}' write_racy_sessions

if [ "$fail" -eq 0 ]; then
  touch "$out"
else
  exit 1
fi
