# shellcheck shell=bash
# splunk-mcp-connect — connects to the Splunk MCP Server via mcp-remote stdio proxy.
#
# Reads credentials from env (injected by doppler-mcp wrapper at MCP launch time).
#
# SECURITY NOTE: Bearer token is visible in process list via --header arg.
# This is a known mcp-remote limitation — no stdin/env-based header injection exists yet.
# Mitigated by: (1) macOS single-user system, (2) Splunk-scoped token with limited
# capabilities, (3) token is rotatable via Doppler.
#
# bun is on PATH via runtimeInputs (writeShellApplication)
: "${SPLUNK_MCP_ENDPOINT:?SPLUNK_MCP_ENDPOINT not set in Doppler}"
: "${SPLUNK_MCP_TOKEN:?SPLUNK_MCP_TOKEN not set in Doppler}"
export NODE_TLS_REJECT_UNAUTHORIZED=0  # Self-signed cert on Splunk; scoped to this process only
exec bunx --bun mcp-remote@0.1.38 \
  "$SPLUNK_MCP_ENDPOINT" \
  --header "Authorization: Bearer $SPLUNK_MCP_TOKEN"
