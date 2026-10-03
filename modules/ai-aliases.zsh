# AI CLI aliases — sourced by nix-home/nix-darwin zsh init
# Managed by nix-ai's programs.zsh.initContent via modules/ai-shell.nix.
# Single source of truth for AI-tool wrapper aliases.

# `claude` (unaliased) resolves via PATH to ~/.local/bin/claude — the pinned
# stable build maintained by Anthropic's claude.ai/install.sh.
# `claude-latest` bypasses the local install and fetches the npm `latest`
# dist-tag of @anthropic-ai/claude-code on every invocation.
alias claude-latest="bunx @anthropic-ai/claude-code@latest"

# --dangerously-skip-permissions variants (aliases chain at command start in zsh).
alias claude-d="claude --dangerously-skip-permissions"
alias claude-latest-d="claude-latest --dangerously-skip-permissions"

# Z.ai subscription launchers. The ordinary `claude` and `codex` commands
# keep their first-party subscriptions; these opt one child process into
# Z.ai. `claude-zai` is a real PATH command (ai-shell.nix, writeShellApplication)
# rather than a zsh function, so it also works from a non-interactive login
# shell — a zsh function is invisible there.

codex-zai() {
  local -a fetch
  if [[ -z "${(P)ZAI_KEY_ENV}" ]]; then
    [[ -n "$ZAI_KEY_COMMAND" ]] \
      || { print -u2 "codex-zai: set $ZAI_KEY_ENV, or ZAI_KEY_COMMAND to fetch it"; return 1; }
    fetch=(${(z)ZAI_KEY_COMMAND})
  fi
  "${fetch[@]}" zsh -c '
      ANTHROPIC_API_KEY= \
      ANTHROPIC_AUTH_TOKEN= \
      OPENAI_API_KEY= \
        exec codex --profile zai "$@"
    ' zsh "$@"
}
