#!/usr/bin/env bash
set -euo pipefail

readonly CONNECT="$1"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin"

# Mocks get an explicit interpreter path: the Nix Linux sandbox has no
# /usr/bin/env, so a `#!/usr/bin/env bash` mock fails exec and every case
# collapses into the same "missing secret-zero" error.
write_mock() {
  printf '#!%s\n' "$BASH" > "$1"
  cat >> "$1"
  chmod +x "$1"
}

write_mock "$TEST_ROOT/bin/curl" <<'EOF'
# Consume piped stdin (--data @- / -H @-) so the writing jq/printf never sees
# EPIPE — real curl reads it; a mock that exits first makes the pipeline flaky.
cat > /dev/null
url="${!#}"
case "$url" in
  */auth/approle/login)
    [ "${TEST_MODE:-}" != login ] || exit 22
    printf '%s\n' '{"auth":{"client_token":"test-bao-token"}}'
    ;;
  */secret/data/ai/mcp/splunk)
    [ "${TEST_MODE:-}" != denied ] || exit 22
    case "${TEST_MODE:-}" in
      incomplete) printf '%s\n' '{"data":{"data":{"SPLUNK_MCP_URL":"https://splunk.example.test/services/mcp"}}}' ;;
      malformed_url) printf '%s\n' '{"data":{"data":{"SPLUNK_MCP_URL":"not-a-url","SPLUNK_MCP_TOKEN":"test-splunk-token"}}}' ;;
      *) printf '%s\n' '{"data":{"data":{"SPLUNK_MCP_URL":"https://splunk.example.test/services/mcp","SPLUNK_MCP_TOKEN":"test-splunk-token"}}}' ;;
    esac
    ;;
  *) exit 22 ;;
esac
EOF

write_mock "$TEST_ROOT/bin/bunx" <<'EOF'
[ "${SPLUNK_MCP_URL:-}" = 'https://splunk.example.test/services/mcp' ]
[ "${SPLUNK_MCP_TOKEN:-}" = 'test-splunk-token' ]
[ "${NODE_TLS_REJECT_UNAUTHORIZED:-}" = 0 ]
[ "$*" = '--bun mcp-remote@0.1.38 https://splunk.example.test/services/mcp --header Authorization: Bearer test-splunk-token' ]
[ "${TEST_MODE:-}" != mcp_failure ]
EOF

run_case() {
  local mode="$1" expected="$2"
  local output
  local secret_id='test-secret'
  [ "$mode" != missing_secret_id ] || secret_id=''
  if output="$(TEST_MODE="$mode" \
    BAO_ADDR='https://bao.example.test' \
    AI_READONLY_ROLE_ID='test-role' \
    AI_READONLY_SECRET_ID="$secret_id" \
    SPLUNK_MCP_CURL_BIN="$TEST_ROOT/bin/curl" \
    SPLUNK_MCP_BUNX_BIN="$TEST_ROOT/bin/bunx" \
    bash "$CONNECT" 2>&1)"; then
    echo "FAIL: $mode unexpectedly succeeded" >&2
    exit 1
  fi
  case "$output" in
    *"$expected"*) ;;
    *) echo "FAIL: $mode returned unexpected output: $output" >&2; exit 1 ;;
  esac
  case "$output" in
    *test-role* | *test-secret* | *test-bao-token* | *test-splunk-token*)
      echo "FAIL: $mode exposed secret material" >&2
      exit 1
      ;;
  esac
}

# No ambient secret-zero at all → fail closed with the runbook pointer.
if output="$(env -u BAO_ADDR -u AI_READONLY_ROLE_ID -u AI_READONLY_SECRET_ID \
  bash "$CONNECT" 2>&1)"; then
  echo "FAIL: missing_env unexpectedly succeeded" >&2
  exit 1
fi
case "$output" in
  *"secret-zero missing from environment"*) ;;
  *) echo "FAIL: missing_env returned unexpected output: $output" >&2; exit 1 ;;
esac

run_case missing_secret_id "secret-zero missing from environment"
run_case login "AppRole login failed"
run_case denied "denied or failed to read"
run_case incomplete "is incomplete"
run_case malformed_url "invalid SPLUNK_MCP_URL"
run_case mcp_failure "MCP connection failed"

TEST_MODE=success \
  BAO_ADDR='https://bao.example.test' \
  AI_READONLY_ROLE_ID='test-role' \
  AI_READONLY_SECRET_ID='test-secret' \
  SPLUNK_MCP_CURL_BIN="$TEST_ROOT/bin/curl" \
  SPLUNK_MCP_BUNX_BIN="$TEST_ROOT/bin/bunx" \
  bash "$CONNECT"

# A child cannot mutate its parent's environment; make the boundary explicit.
[ -z "${SPLUNK_MCP_URL:-}" ]
[ -z "${SPLUNK_MCP_TOKEN:-}" ]

echo "Splunk MCP OpenBao wrapper tests passed"
