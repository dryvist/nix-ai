# AI CLI aliases — sourced by nix-home/nix-darwin zsh init
# Managed by nix-ai's programs.zsh.initContent via modules/ai-shell.nix.
# Single source of truth for Claude/Doppler AI-tool wrapper aliases.

# Secret-zero for OpenBao-backed MCP servers (splunk-mcp-connect) plus the
# Doppler project/config used by the d-* aliases and doppler-mcp. Per the
# ai-agent-access-openbao runbook, these arrive from the ambient environment —
# no literal endpoint, AppRole, or project name is committed to this repo. This
# shell-init injection reads them from the automation Keychain so any harness
# launched from a login shell (Claude Code, Codex, …) inherits them — no
# interactive prompt, and the wrappers' "secret-zero missing" errors stay
# unreachable in normal operation. Values never touch the world-readable Nix
# store; each lives in a Keychain generic-password item whose service name
# equals the variable name. The read is only-if-unset (a `doppler run`-wrapped
# launch that already injects them wins) and silent when an item is absent
# (macOS-only; other stores use `doppler run`).
if [[ "$OSTYPE" == darwin* ]]; then
  for _ai_ro_var in BAO_ADDR AI_READONLY_ROLE_ID AI_READONLY_SECRET_ID SPLUNK_MCP_OPENBAO_PATH AI_DOPPLER_PROJECT AI_DOPPLER_CONFIG; do
    if [[ -z "${(P)_ai_ro_var}" ]]; then
      _ai_ro_val="$(security find-generic-password -s "$_ai_ro_var" -w 2>/dev/null)" \
        && [[ -n "$_ai_ro_val" ]] \
        && export "$_ai_ro_var=$_ai_ro_val"
    fi
  done
  unset _ai_ro_var _ai_ro_val
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
# credentials. Project/config arrive ambiently, see the block above.
# Usage: d-claude               # interactive
#        d-claude -p "prompt"   # non-interactive
alias d-claude='doppler run -p "$AI_DOPPLER_PROJECT" -c "${AI_DOPPLER_CONFIG:-prd}" -- claude'

# Doppler-wrapped agent CLIs — inject AI_DOPPLER_PROJECT/AI_DOPPLER_CONFIG
# secrets for cloud-provider fallback paths (OPENAI_API_KEY, OPENROUTER_API_KEY,
# DASHSCOPE_API_KEY, etc.). Default sessions use local MLX directly; no
# Doppler needed.
alias d-cecli='doppler run -p "$AI_DOPPLER_PROJECT" -c "${AI_DOPPLER_CONFIG:-prd}" -- cecli'
alias d-qwen='doppler run -p "$AI_DOPPLER_PROJECT" -c "${AI_DOPPLER_CONFIG:-prd}" -- qwen'
