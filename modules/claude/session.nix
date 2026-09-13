# Claude Code session-runtime values: the statusline and the event hooks.
#
# Extracted from claude-config.nix to keep that file under the org file-size
# cap, the same reason ./permissions.nix, ./mcp-render.nix, ./marketplaces.nix
# and ./automode.nix live beside it.
{
  # ccstatusline (sirmalloc/ccstatusline) — the statusline that was active in
  # nix-ai before the nix-claude-code migration. Pinned explicitly so it does
  # not fall back to nix-claude-code's powerline default.
  statusline = {
    enable = true;
    theme = "ccstatusline";
  };

  # Event-driven automation for Claude Code.
  #   captureSessionOutput  postToolUse runs the vendored capture script.
  #   refreshMarketplaces   sessionStart runs the vendored refresh helper.
  #   worktreesUnderRepo    worktreeCreate/worktreeRemove place every worktree
  #                         at `<repo>/.worktrees/<name>/`.
  # All three are implemented in nix-claude-code (modules/hooks.nix).
  hooks = {
    captureSessionOutput = true;
    refreshMarketplaces = true;
    worktreesUnderRepo = true;
  };
}
