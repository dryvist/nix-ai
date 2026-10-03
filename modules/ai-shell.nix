# AI shell aliases wiring
#
# Appends AI-tool aliases to programs.zsh.initContent after nix-home's base
# init block. lib.mkAfter ensures these entries load last so any collisions
# with nix-home's aliases.nix win in our favor. The companion nix-home PR
# removes d-claude from that file, but mkAfter keeps us safe
# during the transitional window.

{
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../vars/ai-stack.nix) zai;
in
{
  config = {
    # Non-secret launcher settings. ZAI_KEY_COMMAND, the command the Z.ai
    # launchers use to fetch their key, comes from the host's environment, not
    # from this module. Secret values are never exported here.
    programs.zsh.initContent = lib.mkAfter ''
      export ZAI_KEY_ENV=${lib.escapeShellArg zai.keyEnv}
      export ZAI_CLAUDE_BASE_URL=${lib.escapeShellArg zai.claude.baseUrl}
      export ZAI_CLAUDE_PRIMARY_MODEL=${lib.escapeShellArg zai.claude.primaryModel}
      export ZAI_CLAUDE_FAST_MODEL=${lib.escapeShellArg zai.claude.fastModel}
      export ZAI_CLAUDE_AUTO_COMPACT_WINDOW=${lib.escapeShellArg zai.claude.autoCompactWindow}
      source ${./ai-aliases.zsh}
    '';

    # A real PATH command, not a zsh function: a zsh-function claude-zai is
    # invisible to any non-interactive invocation (a login shell with no
    # tty aborts zsh's interactive init before the function is even
    # defined) — exactly the failure mode the open-llm identity hit.
    # Factored into claude-zai-pkg.nix so lib/checks/scripts/zai-launchers-test.sh
    # builds and tests this exact derivation, not a hand-kept copy of it.
    home.packages = [ (pkgs.callPackage ./claude-zai-pkg.nix { inherit zai; }) ];
  };
}
