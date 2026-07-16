#!/usr/bin/env bash
set -euo pipefail

readonly CONNECT="$1"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin"

cat > "$TEST_ROOT/bin/security" <<'EOF'
#!/usr/bin/env bash
service="" account=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -s) service="$2"; shift 2 ;;
    -a) account="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "${TEST_MODE:-}" = keychain ]; then exit 44; fi
case "$service/$account" in
  openbao/bao_addr) printf '%s\n' 'https://bao.example.test' ;;
  openbao/ai-readonly/role_id) printf '%s\n' 'test-role' ;;
  openbao/ai-readonly/secret_id)
    [ "${TEST_MODE:-}" = missing_approle ] || printf '%s\n' 'test-secret'
    ;;
  *) exit 44 ;;
esac
EOF

cat > "$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
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

cat > "$TEST_ROOT/bin/bunx" <<'EOF'
#!/usr/bin/env bash
[ "${SPLUNK_MCP_URL:-}" = 'https://splunk.example.test/services/mcp' ]
[ "${SPLUNK_MCP_TOKEN:-}" = 'test-splunk-token' ]
[ "${NODE_TLS_REJECT_UNAUTHORIZED:-}" = 0 ]
[ "$*" = '--bun mcp-remote@0.1.38 https://splunk.example.test/services/mcp --header Authorization: Bearer test-splunk-token' ]
[ "${TEST_MODE:-}" != mcp_failure ]
EOF
chmod +x "$TEST_ROOT/bin/security" "$TEST_ROOT/bin/curl" "$TEST_ROOT/bin/bunx"

run_case() {
  local mode="$1" expected="$2"
  local output
  if output="$(TEST_MODE="$mode" \
    SPLUNK_MCP_SECURITY_BIN="$TEST_ROOT/bin/security" \
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

run_case keychain "keychain is locked or unseeded"
run_case missing_approle "keychain is locked or unseeded"
run_case login "AppRole login failed"
run_case denied "denied or failed to read"
run_case incomplete "is incomplete"
run_case malformed_url "invalid SPLUNK_MCP_URL"
run_case mcp_failure "MCP connection failed"

TEST_MODE=success \
  SPLUNK_MCP_SECURITY_BIN="$TEST_ROOT/bin/security" \
  SPLUNK_MCP_CURL_BIN="$TEST_ROOT/bin/curl" \
  SPLUNK_MCP_BUNX_BIN="$TEST_ROOT/bin/bunx" \
  bash "$CONNECT"

# A child cannot mutate its parent's environment; make the boundary explicit.
[ -z "${SPLUNK_MCP_URL:-}" ]
[ -z "${SPLUNK_MCP_TOKEN:-}" ]

echo "Splunk MCP OpenBao wrapper tests passed"
