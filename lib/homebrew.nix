# AI tool Homebrew packages managed by nix-ai.
#
# Single source of truth consumed by:
#   - flake.nix lib exports  → nix-darwin homebrew.nix (host capabilities)
#   - modules/default.nix   → ~/.homebrew/trust.json (macOS only)
#
# Packages are keyed by injected, default-off host capabilities so consumers
# never repeat package names or embed host-class policy.
#
# GUI APPLICATIONS only. Every CLI comes from nixpkgs or the llm-agents.nix
# flake input (Claude Code's install method is nix-claude-code's
# programs.claude.install). A Homebrew cask has no Linux path.
{
  # No vendor tap is required by any cask below.
  taps = [ ];

  brews = {
    langgraphCli = [ "langgraph-cli" ];
  };

  # Untrusted agent CLIs. Emitted by flake/lib.nix homebrewFor only when the
  # host capabilities also carry `untrustedClis = true`, matching
  # programs.ai.untrustedClis.enable on the home-manager side.
  untrustedBrews = {
    goose = [ "block-goose-cli" ];
  };

  casks = {

    claudeDesktop = [
      {
        name = "claude";
        greedy = true;
      }
    ];

    codexDesktop = [
      {
        name = "codex-app";
        greedy = true;
      }
    ];

    chatgptDesktop = [
      {
        name = "chatgpt";
        greedy = true;
      }
    ];

    # Google ships three independent Antigravity products. The `agy` CLI is no
    # longer one of them here — it comes from llm-agents.nix. These two are the
    # GUI halves.
    antigravityDesktop = [
      {
        name = "antigravity";
        greedy = true;
      }
    ];

    antigravityIde = [
      {
        name = "antigravity-ide";
        greedy = true;
      }
    ];
  };
}
