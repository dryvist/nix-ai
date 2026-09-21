# AI CLI aliases — sourced by nix-home/nix-darwin zsh init
# Managed by nix-ai's programs.zsh.initContent via modules/ai-shell.nix.
# Single source of truth for Claude/Doppler AI-tool wrapper aliases.

# Secret-zero for OpenBao-backed commands (the ai-readonly AppRole). Per the
# ai-agent-access-openbao runbook these live in the automation Keychain —
# no literal endpoint or AppRole is committed to this repo. The Doppler
# project/config selectors are not secrets; modules/ai-shell.nix exports them
# from vars/ai-stack.nix, the single source shared with the MCP catalog.
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
    for _ai_ro_var in BAO_ADDR AI_READONLY_ROLE_ID AI_READONLY_SECRET_ID SPLUNK_MCP_OPENBAO_PATH; do
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

# Router API-key shortcut: `aikey <harness>` prints that harness's LiteLLM
# router virtual key, read from OpenBao at call time via the same
# AppRole-login-then-KV-read shape as nix-home's raycast-ai-providers.nix
# merge script — secret-zero from the ambient AI_READONLY_* vars (run it
# through `with-ai-readonly` above if those aren't already in your shell,
# e.g. `with-ai-readonly zsh -i -c 'aikey opencode'` — `-i` is required so the
# interactive-shell function definitions load; a plain `zsh -c` never reads
# them, and the wrapped command still ends in `env`), fail closed, never an
# empty key printed. The value lives only in the caller's shell (e.g.
# `export OPENCODE_API_KEY="$(aikey opencode)"`) — nothing is written to disk.
#   aikey opencode  ->  GET secret/data/apps/opencode, field opencode_llm_router_key
_aikey_skip() { print -u2 "aikey: skipped: no router credential ($1)"; }

aikey() {
  local harness="${1:l}"
  [[ -n "$harness" ]] || { print -u2 "usage: aikey <harness>"; return 1; }

  local path_prefix="${AI_ROUTER_KEY_OPENBAO_PATH_PREFIX:-secret/data/apps}"
  local field_suffix="${AI_ROUTER_KEY_OPENBAO_FIELD_SUFFIX:-_llm_router_key}"
  local openbao_path="${path_prefix%/}/${harness}"
  local key_field="${harness//-/_}${field_suffix}"

  local bao_addr="${BAO_ADDR:-}"
  local role_id="${AI_READONLY_ROLE_ID:-}"
  local secret_id="${AI_READONLY_SECRET_ID:-}"
  [[ -n "$bao_addr" && -n "$role_id" && -n "$secret_id" ]] \
    || { _aikey_skip "OpenBao AppRole secret-zero absent from the environment"; return 1; }
  bao_addr="${bao_addr%/}"

  local login_response
  login_response="$(jq -nc --arg role_id "$role_id" --arg secret_id "$secret_id" \
      '{role_id: $role_id, secret_id: $secret_id}' \
    | curl -fsS --max-time 10 -H "Content-Type: application/json" --data @- \
        "$bao_addr/v1/auth/approle/login" 2>/dev/null)" \
    || { _aikey_skip "OpenBao AppRole login failed"; return 1; }
  local bao_token
  bao_token="$(print -r -- "$login_response" | jq -er '.auth.client_token // empty' 2>/dev/null)" \
    || { _aikey_skip "OpenBao AppRole login response had no client_token"; return 1; }

  local secret_response
  secret_response="$(print -r -- "X-Vault-Token: $bao_token" \
    | curl -fsS --max-time 10 -H @- "$bao_addr/v1/$openbao_path" 2>/dev/null)" \
    || { _aikey_skip "OpenBao denied or failed to read $openbao_path"; return 1; }
  local api_key
  api_key="$(print -r -- "$secret_response" | jq -er --arg f "$key_field" '.data.data[$f] // empty' 2>/dev/null)" \
    || { _aikey_skip "OpenBao secret at $openbao_path has no $key_field field"; return 1; }
  [[ -n "$api_key" ]] || { _aikey_skip "$key_field field is empty"; return 1; }

  print -r -- "$api_key"
}

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

# Z.ai subscription launchers. The ordinary `claude` and `codex` commands keep
# their first-party subscriptions; these opt one child process into Z.ai.
#
# ONE SOURCE PER FACT: the ANTHROPIC_*/model env block lives only in
# _claude_zai_launch. claude-zai calls it with the subscription key from
# Doppler (its normal path); an already-set $ZAI_DOPPLER_KEY_ENV in the
# environment is used as-is instead, with no Doppler call at all -- the path
# an identity with no Doppler token (e.g. open-llm, via openbao-run) takes.
_claude_zai_launch() {
  local key_value="$1"
  shift
  [[ -n "$key_value" ]] || {
    print -u2 "claude-zai: no $ZAI_DOPPLER_KEY_ENV in the environment or Doppler"
    return 1
  }
  ANTHROPIC_API_KEY= \
  ANTHROPIC_AUTH_TOKEN="$key_value" \
  ANTHROPIC_BASE_URL="$ZAI_CLAUDE_BASE_URL" \
  ANTHROPIC_CUSTOM_HEADERS= \
  CLAUDE_CODE_OAUTH_TOKEN= \
  CLAUDE_CODE_USE_BEDROCK= \
  CLAUDE_CODE_USE_VERTEX= \
  OPENAI_API_KEY= \
  ANTHROPIC_DEFAULT_FABLE_MODEL="$ZAI_CLAUDE_PRIMARY_MODEL" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$ZAI_CLAUDE_PRIMARY_MODEL" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$ZAI_CLAUDE_FAST_MODEL" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$ZAI_CLAUDE_FAST_MODEL" \
  CLAUDE_CODE_SUBAGENT_MODEL="$ZAI_CLAUDE_FAST_MODEL" \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW="$ZAI_CLAUDE_AUTO_COMPACT_WINDOW" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  API_TIMEOUT_MS=3000000 \
    exec claude "$@"
}

claude-zai() {
  local key_name="$ZAI_DOPPLER_KEY_ENV"
  local key_value="${(P)key_name}"
  if [[ -n "$key_value" ]]; then
    _claude_zai_launch "$key_value" "$@"
  else
    # zsh functions aren't inherited by an exec'd child (unlike bash's
    # `export -f`), so splice this shell's own definition of
    # _claude_zai_launch into the doppler-launched subshell's script text via
    # `functions` -- one definition, reused, never copy-pasted into the child.
    doppler run \
      -p "$ZAI_DOPPLER_PROJECT" \
      -c "$ZAI_DOPPLER_CONFIG" \
      --no-fallback \
      --only-secrets "$ZAI_DOPPLER_KEY_ENV" -- \
      zsh -c "$(functions _claude_zai_launch)"'
        _claude_zai_launch "${(P)ZAI_DOPPLER_KEY_ENV}" "$@"' zsh "$@"
  fi
}

codex-zai() {
  doppler run \
    -p "$ZAI_DOPPLER_PROJECT" \
    -c "$ZAI_DOPPLER_CONFIG" \
    --no-fallback \
    --only-secrets "$ZAI_DOPPLER_KEY_ENV" -- \
    zsh -c '
      ANTHROPIC_API_KEY= \
      ANTHROPIC_AUTH_TOKEN= \
      OPENAI_API_KEY= \
        exec codex --profile zai "$@"
    ' zsh "$@"
}
