#!/usr/bin/env bash
set -euo pipefail

route_script="${SRC:?}/modules/agent-hooks/agent-route.sh"
config="${SRC}/modules/agent-hooks/agent-route.json"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/codex-quota" <<'EOF'
#!/usr/bin/env bash
exit "${TEST_CODEX_QUOTA_EXIT:-0}"
EOF
cat >"$tmp/bin/zai-quota" <<'EOF'
#!/usr/bin/env bash
exit "${TEST_ZAI_QUOTA_EXIT:-0}"
EOF
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' called >>"$TEST_CURL_LOG"
case "${TEST_VISIBILITY:-public}" in
  public) printf '%s\n' '{"visibility":"public","private":false}' ;;
  private) printf '%s\n' '{"visibility":"private","private":true}' ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$tmp/bin/codex-quota" "$tmp/bin/zai-quota" "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export AGENT_ROUTE_CONFIG="$config"
export CODEX_QUOTA_CMD="$tmp/bin/codex-quota"
export ZAI_QUOTA_CMD="$tmp/bin/zai-quota"
export GITHUB_API_URL=https://api.example.invalid
export TEST_CURL_LOG="$tmp/curl.log"

assert_route() {
  local expected="$1" actual
  shift
  actual=$(bash "$route_script" "$@")
  if [ "$actual" != "$expected" ]; then
    printf 'expected %s, got %s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

export TEST_CODEX_QUOTA_EXIT=0 TEST_ZAI_QUOTA_EXIT=0 TEST_VISIBILITY=public
assert_route codex code-review dryvist/example

export TEST_CODEX_QUOTA_EXIT=1
assert_route zcode code-review dryvist/example

rm -f "$TEST_CURL_LOG"
assert_route opencode-go code-review other/example
[ ! -e "$TEST_CURL_LOG" ]

export TEST_VISIBILITY=unknown
assert_route opencode-go code-review dryvist/example

export TEST_VISIBILITY=public TEST_CODEX_QUOTA_EXIT=0 TEST_ZAI_QUOTA_EXIT=0
assert_route zcode-flash triage dryvist/example

export TEST_ZAI_QUOTA_EXIT=1
assert_route codex triage dryvist/example

rm -f "$TEST_CURL_LOG"
export TEST_CODEX_QUOTA_EXIT=0 TEST_ZAI_QUOTA_EXIT=0
assert_route codex private dryvist/example
[ ! -e "$TEST_CURL_LOG" ]

assert_route stop unknown dryvist/example
printf '%s\n' 'agent-route: all cases behave as expected'
