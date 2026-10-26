#!/usr/bin/env bash
# Test body for the codex-quota check (lib/checks/lint.nix).
# Runs the quota probe against a stub Codex CLI and temporary session data.
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"
script="${SRC}/modules/agent-hooks/codex-quota.sh"

fail=0

expect_case() {
  local label="$1" stub_exit="$2" session_json="$3"
  local expected_status="$4" expected_text="$5"
  local case_dir bin codex_home home output status

  case_dir="$(mktemp -d)"
  bin="$case_dir/bin"
  codex_home="$case_dir/codex-home"
  home="$case_dir/home"
  mkdir -p "$bin" "$codex_home/sessions" "$home" "$case_dir/empty"

  printf '#!/usr/bin/env bash\necho "codex-cli stub"\nexit %s\n' "$stub_exit" > "$bin/codex"
  chmod +x "$bin/codex"

  if [ -n "$session_json" ]; then
    printf '%s\n' "$session_json" > "$codex_home/sessions/rollout-test.jsonl"
  fi

  set +e
  output=$(
    cd "$case_dir/empty"
    PATH="$bin:$PATH" \
      CODEX_HOME="$codex_home" \
      HOME="$home" \
      bash "$script"
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

session_exhausted='{"limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":96,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'
session_available='{"limit_id":"codex","payload":{"rate_limits":{"primary":{"used_percent":10,"resets_at":9999999999},"secondary":{"used_percent":10,"resets_at":9999999999}}}}'

expect_case "CLI cannot run" 127 "" 1 "unavailable"
expect_case "no session files" 0 "" 0 "available"
expect_case "quota exhausted" 0 "$session_exhausted" 1 "exhausted"
expect_case "quota available" 0 "$session_available" 0 "available"

if [ "$fail" -eq 0 ]; then
  touch "$out"
else
  exit 1
fi
