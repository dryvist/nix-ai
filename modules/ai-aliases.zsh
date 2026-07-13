# AI CLI aliases — sourced by nix-home/nix-darwin zsh init
# Managed by nix-ai's programs.zsh.initContent via modules/ai-shell.nix.
# Single source of truth for Claude/Doppler AI-tool wrapper aliases.

# `claude` (unaliased) resolves via PATH to ~/.local/bin/claude — the pinned
# stable build maintained by Anthropic's claude.ai/install.sh.
# `claude-latest` bypasses the local install and fetches the npm `latest`
# dist-tag of @anthropic-ai/claude-code on every invocation.
alias claude-latest="bunx @anthropic-ai/claude-code@latest"

# --dangerously-skip-permissions variants (aliases chain at command start in zsh).
alias claude-d="claude --dangerously-skip-permissions"
alias claude-latest-d="claude-latest --dangerously-skip-permissions"

# Doppler-wrapped Claude — injects ai-ci-automation/prd secrets (GEMINI_API_KEY,
# OPENROUTER_API_KEY, etc.) for sessions that need MCP/API credentials.
# Usage: d-claude               # interactive
#        d-claude -p "prompt"   # non-interactive
alias d-claude="doppler run -p ai-ci-automation -c prd -- claude"

# Doppler-wrapped agent CLIs — inject ai-ci-automation/prd secrets for
# cloud-provider fallback paths (OPENAI_API_KEY, OPENROUTER_API_KEY,
# DASHSCOPE_API_KEY, etc.). Default sessions use local MLX directly; no
# Doppler needed.
alias d-cecli="doppler run -p ai-ci-automation -c prd -- cecli"
alias d-qwen="doppler run -p ai-ci-automation -c prd -- qwen"
