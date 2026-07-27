# AI tool Homebrew casks managed by nix-ai.
# Single source of truth consumed by:
#   - flake.nix lib exports  → nix-darwin homebrew.nix (host capability groups)
#   - modules/default.nix   → ~/.homebrew/trust.json (macOS only)
#
# Casks are keyed by injected host capabilities so consumers never repeat
# package names or embed host-class policy.
{
  # claude-code@latest is now in Homebrew core, so no vendor tap is required.
  taps = [ ];

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

    codexApp = [
      {
        name = "codex-app";
        greedy = true;
      }
    ];

    # antigravity suite ships in the default homebrew-cask tap — no vendor tap needed.
    # `antigravity` (umbrella) already ships the `agy` CLI binary, so the separate
    # `antigravity-cli` cask is omitted — both target /opt/homebrew/bin/agy and
    # collide ("already a Binary at '/opt/homebrew/bin/agy'") during brew bundle.
    antigravity = [
      {
        name = "antigravity";
        greedy = true;
      }
      {
        name = "antigravity-ide";
        greedy = true;
      }
    ];
  };
}
