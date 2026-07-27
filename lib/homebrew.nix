# AI tool Homebrew packages managed by nix-ai.
# Single source of truth consumed by:
#   - flake.nix lib exports  → nix-darwin homebrew.nix (host capabilities)
#   - modules/default.nix   → ~/.homebrew/trust.json (macOS only)
#
# Packages are keyed by injected, default-off host capabilities so consumers
# never repeat package names or embed host-class policy.
{
  # claude-code@latest is now in Homebrew core, so no vendor tap is required.
  taps = [ ];

  brews = {
    goose = [ "block-goose-cli" ];
    qwenCode = [ "qwen-code" ];
  };

  casks = {
    claudeCode = [
      {
        name = "claude-code@latest";
        greedy = true;
      }
    ];

    codex = [
      {
        name = "codex";
        greedy = true;
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

    # Google ships three independent Antigravity products. The standalone
    # desktop no longer provides `agy`; the CLI cask owns that binary.
    antigravityCli = [
      {
        name = "antigravity-cli";
        greedy = true;
      }
    ];

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
