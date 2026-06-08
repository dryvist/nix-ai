# AI tool Homebrew taps and casks managed by nix-ai.
# Single source of truth consumed by:
#   - flake.nix lib exports  → nix-darwin homebrew.nix (taps + casks)
#   - modules/default.nix   → ~/.homebrew/trust.json (macOS only)
#
# Homebrew 5.2.0/6.0.0 enforces HOMEBREW_REQUIRE_TAP_TRUST. Having the tap
# list here means adding a new AI tap is one edit that updates both the
# nix-darwin tap declaration and the trust.json simultaneously.
{
  taps = [
    "anthropics/tap" # claude-code@latest
    "aws/tap"
  ];

  casks = [
    {
      name = "claude-code@latest";
      greedy = true;
    }
    # antigravity suite ships in the default homebrew-cask tap — no vendor tap needed
    {
      name = "antigravity";
      greedy = true;
    }
    {
      name = "antigravity-cli";
      greedy = true;
    }
    {
      name = "antigravity-ide";
      greedy = true;
    }
  ];
}
