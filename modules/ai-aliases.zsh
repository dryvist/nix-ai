# AI CLI aliases — sourced by nix-home/nix-darwin zsh init
# Managed by nix-ai's programs.zsh.initContent via modules/ai-shell.nix.
# Single source of truth for Claude/Doppler AI-tool wrapper aliases.

# Bleeding-edge native install managed by nix-ai's programs.claude-latest module.
# `claude` (unaliased) resolves via PATH — whatever that points at is intentional.
alias claude-latest="$HOME/.local/bin/claude"

# --dangerously-skip-permissions variants (aliases chain at command start in zsh).
alias claude-d="claude --dangerously-skip-permissions"
alias claude-latest-d="claude-latest --dangerously-skip-permissions"

# Doppler-wrapped Claude — injects ai-ci-automation/prd secrets (GEMINI_API_KEY,
# OPENROUTER_API_KEY, etc.) for sessions that need MCP/API credentials.
# Usage: d-claude               # interactive
#        d-claude -p "prompt"   # non-interactive
alias d-claude="doppler run -p ai-ci-automation -c prd -- claude"

# aws-vault terraform profile layered on top of d-claude. For infra-repo sessions
# that need BOTH AWS credentials AND AI MCP secrets loaded.
alias tf-claude="aws-vault exec terraform -- doppler run -p ai-ci-automation -c prd -- claude"

# Doppler-wrapped Aider — injects ai-ci-automation/prd secrets for cloud-provider
# fallback paths (OPENAI_API_KEY, OPENROUTER_API_KEY, etc.).
# Default sessions use local MLX directly; no Doppler needed.
alias d-aider="doppler run -p ai-ci-automation -c prd -- aider"
