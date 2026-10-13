#!/usr/bin/env bash
set -euo pipefail

script="${SRC:?}/modules/agent-hooks/agent-routing-context.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/repo"
git -C "$tmp/repo" init -q
git -C "$tmp/repo" remote add origin git@github.com:dryvist/example.git
cat >"$tmp/bin/agent-route" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  code-review) printf '%s\n' "${TEST_CODE_REVIEW:-codex}" ;;
  triage) printf '%s\n' "${TEST_TRIAGE:-zcode-flash}" ;;
  private) printf '%s\n' "${TEST_PRIVATE:-opencode-go}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/agent-route"
export AGENT_ROUTE_CMD="$tmp/bin/agent-route"
export TEST_CODE_REVIEW=zcode TEST_TRIAGE=codex TEST_PRIVATE=haiku-high

output="$(jq -nc --arg cwd "$tmp/repo" '{cwd: $cwd}' | bash "$script")"
jq -e '.hookSpecificOutput.hookEventName == "SubagentStart" and
  (.hookSpecificOutput.additionalContext | contains("code-review=zcode; triage=codex; private=haiku-high")) and
  (.hookSpecificOutput.additionalContext | contains("Private ladder: codex -> opencode-go -> haiku-high."))' \
  <<<"$output" >/dev/null
line_count="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output" | wc -l | tr -d ' ')"
[ "$line_count" -le 25 ]

printf '%s\n' 'agent-routing-context: hook output and routing preamble are valid'
