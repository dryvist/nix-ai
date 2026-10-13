#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
cwd="$(jq -r '.cwd // ""' <<<"$input")"
cwd="${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"
repo=""
remote="$(git -C "$cwd" remote get-url origin 2>/dev/null || true)"
case "$remote" in
  git@github.com:*) remote="${remote#git@github.com:}" ;;
  ssh://git@github.com/*) remote="${remote#ssh://git@github.com/}" ;;
  https://github.com/*) remote="${remote#https://github.com/}" ;;
  http://github.com/*) remote="${remote#http://github.com/}" ;;
  *) remote="" ;;
esac
remote="${remote%.git}"
if [[ $remote =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]]; then
  repo="$remote"
fi

route_cmd="${AGENT_ROUTE_CMD:-agent-route}"
route_answer() {
  local kind answer
  kind="$1"
  if [ -n "$repo" ]; then
    answer="$("$route_cmd" "$kind" "$repo" 2>/dev/null || true)"
  else
    answer="$("$route_cmd" "$kind" 2>/dev/null || true)"
  fi
  case "$answer" in
    codex | zcode | zcode-flash | opencode-go | haiku-high | stop) printf '%s\n' "$answer" ;;
    *) printf '%s\n' stop ;;
  esac
}

code_review="$(route_answer code-review)"
triage="$(route_answer triage)"
private="$(route_answer private)"
context="$(cat <<EOF
Automatic delegation routing:
Use agent-route for each task: code-review for coding/review, triage for public material, private for private data/secrets/live infrastructure.
Code/review ladder: codex -> zcode -> opencode-go -> haiku-high.
Triage ladder: zcode-flash -> codex -> haiku-high.
Private ladder: codex -> opencode-go -> haiku-high.
Current answers for this repository: code-review=$code_review; triage=$triage; private=$private. Quota state is reflected in these answers.
Use zcode-agent code|review|triage <owner/repo> -p <prompt-file> -o <out-file> when the route selects zcode or zcode-flash.
ZCode is limited to public repositories owned by dryvist, JacobPEvans, or JacobPEvans-personal and in the installed repository subset.
Never send secrets, private or unknown-visibility repositories, or live infrastructure work to ZCode.
Code tasks may request a DRAFT PR. Review and triage tasks do not.
After a Z.ai quota/429, zai-quota records an expiring marker so the next route call escalates.
EOF
)"
jq -n --arg context "$context" \
  '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $context}}'
