# AI CLI aliases — sourced by nix-home/nix-darwin zsh init
# Managed by nix-ai's programs.zsh.initContent via modules/ai-shell.nix.
# Single source of truth for Claude/Doppler AI-tool wrapper aliases.

# Doppler selectors for the d-* aliases and doppler-mcp. These are selectors,
# not credentials — no literal project name is committed to this repo, and the
# secrets they select stay in Doppler/OpenBao.
#
# This list used to also carry the OpenBao AppRole id/secret and the Splunk
# secret path so `splunk-mcp-connect` could read them ambiently. That coupled a
# working MCP server to "was this harness started from an interactive zsh",
# which is false for anything launched from a GUI or launchd — and the loop
# below skipped absent items silently, so a missing Keychain item surfaced only
# as an unhelpful "connection closed during initialize" in every client. Those
# values now come from Doppler at launch (see modules/mcp/catalog.nix), leaving
# only selectors here.
#
# The read is only-if-unset, so a `doppler run`-wrapped launch that already
# injects them wins (macOS-only; other stores use `doppler run`).
if [[ "$OSTYPE" == darwin* ]]; then
  for _ai_ro_var in BAO_ADDR AI_DOPPLER_PROJECT AI_DOPPLER_CONFIG; do
    if [[ -z "${(P)_ai_ro_var}" ]]; then
      _ai_ro_val="$(security find-generic-password -s "$_ai_ro_var" -w 2>/dev/null)" \
        && [[ -n "$_ai_ro_val" ]] \
        && export "$_ai_ro_var=$_ai_ro_val"
    fi
  done
  # Fail loudly. AI_DOPPLER_PROJECT is what every Doppler-wrapped MCP server
  # resolves its secrets through; without it they all fail at initialize with no
  # indication why. AI_DOPPLER_CONFIG is deliberately not checked — doppler-mcp
  # defaults it to `prd`. Silence here is what hid the previous breakage.
  if [[ -z "$AI_DOPPLER_PROJECT" ]]; then
    print -u2 "nix-ai: AI_DOPPLER_PROJECT is unset and no Keychain item supplied it;" \
      "Doppler-backed MCP servers will fail to start." \
      "See the ai-agent-access-openbao runbook."
  fi
  unset _ai_ro_var _ai_ro_val
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
