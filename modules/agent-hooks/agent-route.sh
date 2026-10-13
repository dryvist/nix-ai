#!/usr/bin/env bash
set -euo pipefail

kind="${1:-}"
repo="${2:-}"
if [ "$#" -gt 2 ] || ! jq -e --arg kind "$kind" '.ladders | has($kind)' "${AGENT_ROUTE_CONFIG:?}" >/dev/null; then
  printf '%s\n' stop
  exit 0
fi

public=false
owner_allowed=false
if [ "$kind" != private ] && [[ $repo =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]] &&
  [ "${repo#*/}" != . ] && [ "${repo#*/}" != .. ]; then
  owner="${repo%%/*}"
  if jq -e --arg owner "$owner" \
    '.owners | map(ascii_downcase) | index($owner | ascii_downcase) != null' \
    "${AGENT_ROUTE_CONFIG}" >/dev/null; then
    owner_allowed=true
    api_url="${GITHUB_API_URL:-https://api.github.com}"
    metadata=$(curl --fail --silent --show-error --connect-timeout 2 --max-time 5 \
      --header 'Accept: application/vnd.github+json' \
      --header 'X-GitHub-Api-Version: 2022-11-28' \
      "${api_url%/}/repos/$repo" 2>/dev/null || true)
    if jq -e '.visibility == "public" and .private == false' <<<"$metadata" >/dev/null 2>&1; then
      public=true
    fi
  fi
fi

codex_quota="${CODEX_QUOTA_CMD:-codex-quota}"
zai_quota="${ZAI_QUOTA_CMD:-zai-quota}"
while IFS= read -r executor; do
  case "$executor" in
    codex)
      if "$codex_quota" >/dev/null 2>&1; then
        printf '%s\n' "$executor"
        exit 0
      fi
      ;;
    zcode | zcode-flash)
      if [ "$public" = true ] && [ "$owner_allowed" = true ] && "$zai_quota" >/dev/null 2>&1; then
        printf '%s\n' "$executor"
        exit 0
      fi
      ;;
    opencode-go | haiku-high)
      printf '%s\n' "$executor"
      exit 0
      ;;
    stop)
      break
      ;;
  esac
done < <(jq -r --arg kind "$kind" '.ladders[$kind][]' "${AGENT_ROUTE_CONFIG}")

printf '%s\n' stop
