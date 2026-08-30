# AI tool Homebrew packages managed by nix-ai.
#
# Single source of truth consumed by:
#   - flake.nix lib exports  → nix-darwin homebrew.nix (host capabilities)
#   - modules/default.nix   → ~/.homebrew/trust.json (macOS only)
#
# Packages are keyed by injected, default-off host capabilities so consumers
# never repeat package names or embed host-class policy.
#
# GUI APPLICATIONS ONLY. Every CLI that used to live here — claude-code@latest,
# codex, antigravity-cli, qwen-code — now comes from nixpkgs or the
# llm-agents.nix flake input, because a Homebrew cask has no Linux path and so
# pinned the whole AI stack to the MacBook. Do not add a CLI back here: check
# nixpkgs first, then llm-agents.nix, and only then reach for a cask.
{
  # No vendor tap is required for any of the GUI casks below.
  taps = [ ];

  brews = {
    goose = [ "block-goose-cli" ];
    langgraphCli = [ "langgraph-cli" ];
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
