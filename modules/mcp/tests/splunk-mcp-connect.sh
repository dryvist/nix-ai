#!/usr/bin/env bash
set -euo pipefail

readonly CONNECT="$1"
readonly SPLUNK_TOKEN_SENTINEL='splunk-token-MUST-NOT-LEAK'
export SPLUNK_TOKEN_SENTINEL
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
  */"$SPLUNK_MCP_OPENBAO_PATH")
    [ "${TEST_MODE:-}" != denied ] || exit 22
    case "${TEST_MODE:-}" in
      incomplete) printf '%s\n' '{"data":{"data":{"SPLUNK_MCP_URL":"https://splunk.example.test/services/mcp"}}}' ;;
      malformed_url) printf '%s\n' "{\"data\":{\"data\":{\"SPLUNK_MCP_URL\":\"not-a-url\",\"SPLUNK_MCP_TOKEN\":\"$SPLUNK_TOKEN_SENTINEL\"}}}" ;;
      *) printf '%s\n' "{\"data\":{\"data\":{\"SPLUNK_MCP_URL\":\"https://splunk.example.test/services/mcp\",\"SPLUNK_MCP_TOKEN\":\"$SPLUNK_TOKEN_SENTINEL\"}}}" ;;
    esac
    ;;
  *) exit 22 ;;
esac
EOF

write_mock "$TEST_ROOT/bin/bunx" <<'EOF'
[ "${SPLUNK_MCP_URL:-}" = 'https://splunk.example.test/services/mcp' ]
[ "${SPLUNK_MCP_AUTH_HEADER:-}" = "Bearer $SPLUNK_TOKEN_SENTINEL" ]
[ -z "${SPLUNK_MCP_TOKEN:-}" ]
[ "${NODE_TLS_REJECT_UNAUTHORIZED:-}" = 0 ]
[ "$*" = '--bun mcp-remote@0.1.38 https://splunk.example.test/services/mcp --header Authorization:${SPLUNK_MCP_AUTH_HEADER}' ]
if [ "${TEST_MODE:-}" = mcp_failure ]; then
  echo 'mock bunx failed' >&2
  exit 1
fi
if [ "${TEST_MODE:-}" = mcp_diagnostics ]; then
  printf 'mock bunx stdout: %s\n' "$*"
  printf 'mock bunx stderr: %s\n' "$*" >&2
  exit 1
fi
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
    SPLUNK_MCP_OPENBAO_PATH='secret/data/test/mcp-fixture' \
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
    *test-role* | *test-secret* | *test-bao-token* | *"$SPLUNK_TOKEN_SENTINEL"*)
      echo "FAIL: $mode exposed secret material" >&2
      exit 1
      ;;
  esac
}

# No ambient secret-zero at all → fail closed with the runbook pointer.
if output="$(env -u BAO_ADDR -u AI_READONLY_ROLE_ID -u AI_READONLY_SECRET_ID \
  -u SPLUNK_MCP_OPENBAO_PATH \
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
run_case mcp_failure "mock bunx failed"

# mcp-remote logs its custom header before expanding environment placeholders.
# Preserve those diagnostics while ensuring neither output stream sees the value.
stdout="$TEST_ROOT/mcp.stdout"
stderr="$TEST_ROOT/mcp.stderr"
if TEST_MODE=mcp_diagnostics \
  BAO_ADDR='https://bao.example.test' \
  AI_READONLY_ROLE_ID='test-role' \
  AI_READONLY_SECRET_ID='test-secret' \
  SPLUNK_MCP_OPENBAO_PATH='secret/data/test/mcp-fixture' \
  SPLUNK_MCP_CURL_BIN="$TEST_ROOT/bin/curl" \
  SPLUNK_MCP_BUNX_BIN="$TEST_ROOT/bin/bunx" \
  bash "$CONNECT" >"$stdout" 2>"$stderr"; then
  echo "FAIL: mcp_diagnostics unexpectedly succeeded" >&2
  exit 1
fi
grep -F "Authorization:\${SPLUNK_MCP_AUTH_HEADER}" "$stdout" >/dev/null
grep -F "Authorization:\${SPLUNK_MCP_AUTH_HEADER}" "$stderr" >/dev/null
if grep -F "$SPLUNK_TOKEN_SENTINEL" "$stdout" "$stderr" >/dev/null; then
  echo "FAIL: mcp_diagnostics exposed the Splunk token" >&2
  exit 1
fi

TEST_MODE=success \
  BAO_ADDR='https://bao.example.test' \
  AI_READONLY_ROLE_ID='test-role' \
  AI_READONLY_SECRET_ID='test-secret' \
  SPLUNK_MCP_OPENBAO_PATH='secret/data/test/mcp-fixture' \
  SPLUNK_MCP_CURL_BIN="$TEST_ROOT/bin/curl" \
  SPLUNK_MCP_BUNX_BIN="$TEST_ROOT/bin/bunx" \
  bash "$CONNECT"

# A child cannot mutate its parent's environment; make the boundary explicit.
[ -z "${SPLUNK_MCP_URL:-}" ]
[ -z "${SPLUNK_MCP_TOKEN:-}" ]
[ -z "${SPLUNK_MCP_AUTH_HEADER:-}" ]

echo "Splunk MCP OpenBao wrapper tests passed"
