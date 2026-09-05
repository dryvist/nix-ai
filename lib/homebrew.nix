# AI tool Homebrew packages managed by nix-ai.
#
# Single source of truth consumed by:
#   - flake.nix lib exports  → nix-darwin homebrew.nix (host capabilities)
#   - modules/default.nix   → ~/.homebrew/trust.json (macOS only)
#
# Packages are keyed by injected, default-off host capabilities so consumers
# never repeat package names or embed host-class policy.
#
# GUI APPLICATIONS, plus a closed two-entry exception: the CLIs that must track
# upstream faster than the Nix bump cycle.
#
# Every other CLI that used to live here — antigravity-cli, qwen-code among
# them — now comes from nixpkgs or the llm-agents.nix flake input, because a
# Homebrew cask has no Linux path and so pinned the whole AI stack to one
# machine. That reason still holds. Check nixpkgs first, llm-agents.nix second,
# a cask only as a last resort.
#
# The exception is claude-code@latest and codex, below, and it stays narrow:
#   - darwin only. Both are additive to a Nix-declared configuration, never a
#     replacement, and neither is the fleet's source — Linux still takes both
#     from llm-agents.nix, unchanged.
#   - cadence only. Both track upstream within days, and a Nix-side bump costs
#     a relock, a PR and an interactive rebuild. Nothing much needs that.
# A third entry requires the same justification, in writing, at the entry.
{
  # No vendor tap is required by any cask below.
  taps = [ ];

  brews = {
    goose = [ "block-goose-cli" ];
    langgraphCli = [ "langgraph-cli" ];
  };

  casks = {
    # The two-entry CLI exception documented at the top of this file. Homebrew
    # owns these binaries on darwin; nix-ai still owns all of their
    # configuration, and skips only the binary (package = null).
    #
    # greedy = false is deliberate and measured: `brew outdated --cask` lists
    # both without --greedy, so a plain `brew upgrade` already catches them.
    claudeCode = [
      {
        name = "claude-code@latest";
        greedy = false;
      }
    ];

    codex = [
      {
        name = "codex";
        greedy = false;
      }
    ];

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
