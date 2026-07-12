# doppler-mcp — wraps any command with Doppler secret injection.
#
# Fetches secrets from ai-ci-automation/prd at subprocess launch time.
# Secrets are never stored in plaintext — an encrypted fallback cache
# ($XDG_STATE_HOME/doppler-mcp-fallback.enc) provides offline resilience.
# Auth failures exit non-zero (doppler run native behaviour — clear stderr).
#
# Logs invocations (command + args only, no secret values) for audit trail.
# Log: $XDG_STATE_HOME/doppler-mcp.log
#
# IMPORTANT: No synchronous preflight check.
# A `doppler run -- true` preflight previously caused 100% MCP startup failures
# in Claude Code: when ~17 servers launch in parallel, the Doppler API round-trip
# delayed the MCP stdio handshake past Claude Code's connection timeout.
# The preflight also fetched secrets twice (check + real exec). Removed 2026-03-25.
# See modules/mcp/README.md → Troubleshooting for the full story.
#
# doppler is on PATH via runtimeInputs (writeShellApplication)
if [ "$#" -lt 1 ]; then
  echo "Usage: doppler-mcp <command> [args...]" >&2
  echo "Wraps a command with: doppler run -p ai-ci-automation -c prd -- <command> [args...]" >&2
  exit 1
fi
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_FILE="$STATE_DIR/doppler-mcp.log"
# Non-fatal logging — never prevent MCP server launch
{
  mkdir -p "$STATE_DIR"
  touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
  echo "$(date -u +%FT%TZ) doppler-mcp starting: $(printf '%q ' "$@")" >> "$LOG_FILE"
} 2>/dev/null || true
FALLBACK="$STATE_DIR/doppler-mcp-fallback.enc"
exec doppler run -p ai-ci-automation -c prd \
  --fallback "$FALLBACK" \
  -- "$@"
