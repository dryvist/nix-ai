#!/usr/bin/env bash
# Test body for the codex-quota check (lib/checks/lint.nix).
# Runs the quota probe against a stub Codex CLI and temporary session data.
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"
script="${SRC}/modules/agent-hooks/codex-quota.sh"

fail=0

expect_case() {
  local label="$1" stub_exit="$2" session_json="$3"
  local expected_status="$4" expected_text="$5" setup_fn="${6:-}"
  local case_dir bin codex_home home output status

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
  output=$(
    cd "$case_dir/empty"
    PATH="$bin:$PATH" \
      CODEX_HOME="$codex_home" \
      HOME="$home" \
      bash "$script" 2>&1
  )
  status=$?
  set -e

  rm -rf "$case_dir"
  if [ "$status" -eq "$expected_status" ] && [[ "$output" == *"$expected_text"* ]]; then
    echo "PASS ($label): exit $status and output contains '$expected_text'"
  else
    echo "FAIL ($label): expected exit $expected_status and output containing '$expected_text'; got exit $status" >&2
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

session_exhausted='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":96,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'
session_available='{"timestamp":"2026-11-08T00:00:00.000Z","limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":10,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'

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

expect_case "CLI cannot run" 127 "" 1 "unavailable"
expect_missing_cli
expect_case "no session files" 0 "" 0 "available"
expect_case "quota exhausted" 0 "$session_exhausted" 1 "exhausted"
expect_case "quota available" 0 "$session_available" 0 "available"
expect_case "newest timestamp wins over newest mtime" 0 "" 1 '"p":96' write_racy_sessions

if [ "$fail" -eq 0 ]; then
  touch "$out"
else
  exit 1
fi
