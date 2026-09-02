# AI CLI aliases — sourced by nix-home/nix-darwin zsh init
# Managed by nix-ai's programs.zsh.initContent via modules/ai-shell.nix.
# Single source of truth for Claude/Doppler AI-tool wrapper aliases.

# Secret-zero for OpenBao-backed MCP servers (splunk-mcp-connect) plus the
# Doppler project/config used by the d-* aliases and doppler-mcp. Per the
# ai-agent-access-openbao runbook these live in the automation Keychain —
# no literal endpoint, AppRole, or project name is committed to this repo.
#
# `with-ai-readonly <cmd> [args...]` fetches them at call time and exports
# them ONLY into that one child process, not into the login shell (and not
# into every other process a login shell later spawns). Values never touch
# the world-readable Nix store; each lives in a Keychain generic-password
# item scoped to the automation account/db, service name == variable name.
if [[ "$OSTYPE" == darwin* ]]; then
  with-ai-readonly() {
    [[ "$#" -ge 1 ]] || { print -u2 "usage: with-ai-readonly <cmd> [args...]"; return 1; }
    local -a _ai_ro_env
    local _ai_ro_var _ai_ro_val
    for _ai_ro_var in BAO_ADDR AI_READONLY_ROLE_ID AI_READONLY_SECRET_ID SPLUNK_MCP_OPENBAO_PATH AI_DOPPLER_PROJECT AI_DOPPLER_CONFIG; do
      if [[ -n "${(P)_ai_ro_var}" ]]; then
        _ai_ro_env+=("$_ai_ro_var=${(P)_ai_ro_var}")
      else
        _ai_ro_val="$(security find-generic-password -a ai-cli-coder -s "$_ai_ro_var" -w automation.keychain-db 2>/dev/null)" \
          && [[ -n "$_ai_ro_val" ]] \
          && _ai_ro_env+=("$_ai_ro_var=$_ai_ro_val")
      fi
    done
    env "${_ai_ro_env[@]}" "$@"
  }
fi

# Router API-key shortcut (macOS keychain only): `aikey <HARNESS>` prints the
# value of the <HARNESS>_ROUTER_API_KEY generic-password item, e.g.
#   aikey OPENCODE  ->  security find-generic-password -s OPENCODE_ROUTER_API_KEY -w
if [[ "$OSTYPE" == darwin* ]]; then
  aikey() {
    [[ -n "$1" ]] || { print -u2 "usage: aikey <harness>"; return 1; }
    security find-generic-password -s "${1}_ROUTER_API_KEY" -w
  }
fi

# `claude` (unaliased) resolves via PATH to ~/.local/bin/claude — the pinned
# stable build maintained by Anthropic's claude.ai/install.sh.
# `claude-latest` bypasses the local install and fetches the npm `latest`
# dist-tag of @anthropic-ai/claude-code on every invocation.
alias claude-latest="bunx @anthropic-ai/claude-code@latest"

# --dangerously-skip-permissions variants (aliases chain at command start in zsh).
alias claude-d="claude --dangerously-skip-permissions"
alias claude-latest-d="claude-latest --dangerously-skip-permissions"

# Doppler-wrapped Claude — injects AI_DOPPLER_PROJECT/AI_DOPPLER_CONFIG secrets
# (GEMINI_API_KEY, OPENROUTER_API_KEY, etc.) for sessions that need MCP/API
# credentials. with-ai-readonly (above) fetches the project/config into only
# this one child process.
# Usage: d-claude               # interactive
#        d-claude -p "prompt"   # non-interactive
alias d-claude='with-ai-readonly zsh -c '\''doppler run -p "$AI_DOPPLER_PROJECT" -c "${AI_DOPPLER_CONFIG:-prd}" -- claude "$@"'\'' _'

# Doppler-wrapped agent CLIs — inject AI_DOPPLER_PROJECT/AI_DOPPLER_CONFIG
# secrets for cloud-provider fallback paths (OPENAI_API_KEY, OPENROUTER_API_KEY,
# DASHSCOPE_API_KEY, etc.). Default sessions use local MLX directly; no
# Doppler needed.
alias d-cecli='with-ai-readonly zsh -c '\''doppler run -p "$AI_DOPPLER_PROJECT" -c "${AI_DOPPLER_CONFIG:-prd}" -- cecli "$@"'\'' _'
alias d-qwen='with-ai-readonly zsh -c '\''doppler run -p "$AI_DOPPLER_PROJECT" -c "${AI_DOPPLER_CONFIG:-prd}" -- qwen "$@"'\'' _'
