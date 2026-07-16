# shellcheck shell=bash
set -euo pipefail

# splunk-mcp-connect — fetches the shared Splunk MCP connection from OpenBao,
# then connects via the mcp-remote stdio proxy.
#
# SECURITY NOTE: Bearer token is visible in process list via --header arg.
# This is a known mcp-remote limitation — no stdin/env-based header injection exists yet.
# Mitigated by: (1) macOS single-user system, (2) Splunk-scoped token with limited
# capabilities, (3) token is rotatable in OpenBao.
#
# curl, jq, and bun are on PATH via runtimeInputs (writeShellApplication).

readonly KEYCHAIN="${HOME}/Library/Keychains/openbao.keychain-db"
readonly SECURITY_BIN="${SPLUNK_MCP_SECURITY_BIN:-/usr/bin/security}"
readonly CURL_BIN="${SPLUNK_MCP_CURL_BIN:-curl}"
readonly JQ_BIN="${SPLUNK_MCP_JQ_BIN:-jq}"
readonly BUNX_BIN="${SPLUNK_MCP_BUNX_BIN:-bunx}"

die() {
  echo "splunk-mcp-connect: $*" >&2
  exit 1
}

read_keychain_item() {
  "$SECURITY_BIN" find-generic-password \
    -s "$1" -a "$2" -w "$KEYCHAIN" 2>/dev/null
}

bao_addr="$(read_keychain_item openbao bao_addr)" \
  || die "OpenBao keychain is locked or unseeded"
role_id="$(read_keychain_item openbao/ai-readonly role_id)" \
  || die "OpenBao keychain is locked or unseeded"
secret_id="$(read_keychain_item openbao/ai-readonly secret_id)" \
  || die "OpenBao keychain is locked or unseeded"

if [ -z "$bao_addr" ] || [ -z "$role_id" ] || [ -z "$secret_id" ]; then
  die "OpenBao keychain is locked or unseeded"
fi

login_response="$($JQ_BIN -nc --arg role_id "$role_id" --arg secret_id "$secret_id" \
  '{role_id: $role_id, secret_id: $secret_id}' | \
  $CURL_BIN -fsS --max-time 10 \
    -H "Content-Type: application/json" --data @- \
    "$bao_addr/v1/auth/approle/login" 2>/dev/null)" \
  || die "OpenBao AppRole login failed"
bao_token="$(printf '%s' "$login_response" | "$JQ_BIN" -er '.auth.client_token // empty' 2>/dev/null)" \
  || die "OpenBao AppRole login failed"

secret_response="$(printf 'X-Vault-Token: %s\n' "$bao_token" | \
  $CURL_BIN -fsS --max-time 10 -H @- \
    "$bao_addr/v1/secret/data/ai/mcp/splunk" 2>/dev/null)" \
  || die "OpenBao denied or failed to read secret/ai/mcp/splunk"
splunk_mcp_url="$(printf '%s' "$secret_response" | "$JQ_BIN" -er '.data.data.SPLUNK_MCP_URL // empty' 2>/dev/null)" \
  || die "OpenBao secret/ai/mcp/splunk is incomplete"
splunk_mcp_token="$(printf '%s' "$secret_response" | "$JQ_BIN" -er '.data.data.SPLUNK_MCP_TOKEN // empty' 2>/dev/null)" \
  || die "OpenBao secret/ai/mcp/splunk is incomplete"

case "$splunk_mcp_url" in
  https://*/services/mcp | https://*/services/mcp/) ;;
  *) die "OpenBao secret/ai/mcp/splunk has an invalid SPLUNK_MCP_URL" ;;
esac

# These exports exist only in this wrapper and its MCP child. The AppRole,
# OpenBao token, and Splunk values are never exported to the parent shell.
export SPLUNK_MCP_URL="$splunk_mcp_url"
export SPLUNK_MCP_TOKEN="$splunk_mcp_token"
export NODE_TLS_REJECT_UNAUTHORIZED=0

if ! "$BUNX_BIN" --bun mcp-remote@0.1.38 \
  "$SPLUNK_MCP_URL" \
  --header "Authorization: Bearer $SPLUNK_MCP_TOKEN"; then
  die "MCP connection failed"
fi
