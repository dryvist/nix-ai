# shellcheck shell=bash
# doppler-mcp — wraps any command with Doppler secret injection.
#
# Fetches secrets from the AI_DOPPLER_PROJECT/AI_DOPPLER_CONFIG project at
# subprocess launch time (see modules/ai-aliases.zsh for how these arrive
# ambiently). Secrets are never stored in plaintext — an encrypted fallback
# cache ($XDG_STATE_HOME/doppler-mcp-fallback.enc) provides offline resilience.
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
#
# Fallback: macOS login-keychain lookup by service name only (no account or
# custom keychain-file scoping — those would be environment-specific identity
# and don't belong in a public repo). Login-shell ambient export of these vars
# was removed 2026-09-02 (see modules/ai-aliases.zsh's with-ai-readonly) for a
# real security reason, so this process must be able to fetch its own copy.
if command -v security >/dev/null 2>&1; then
  [ -n "${AI_DOPPLER_PROJECT:-}" ] || AI_DOPPLER_PROJECT="$(security find-generic-password -s AI_DOPPLER_PROJECT -w 2>/dev/null || true)"
  [ -n "${AI_DOPPLER_CONFIG:-}" ] || AI_DOPPLER_CONFIG="$(security find-generic-password -s AI_DOPPLER_CONFIG -w 2>/dev/null || true)"
fi
if [ "$#" -lt 1 ] || [ -z "${AI_DOPPLER_PROJECT:-}" ]; then
  echo "Usage: doppler-mcp <command> [args...]" >&2
  echo "Wraps a command with: doppler run -p \$AI_DOPPLER_PROJECT -c \${AI_DOPPLER_CONFIG:-prd} -- <command> [args...]" >&2
  echo "AI_DOPPLER_PROJECT must be set — see the ai-agent-access-openbao runbook." >&2
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
exec doppler run -p "$AI_DOPPLER_PROJECT" -c "${AI_DOPPLER_CONFIG:-prd}" \
  --fallback "$FALLBACK" \
  -- "$@"
