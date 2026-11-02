#
# Fabric Module — Aggregator
#
# Daniel Miessler's Fabric (github.com/danielmiessler/fabric) provides 252+
# reusable AI prompt patterns. This module:
#
#   1. Builds the fabric Go CLI from the fabric-src flake input (package.nix)
#   2. Adds `fabric` to home.packages (packages.nix)
#   3. Symlinks fabric's data/patterns/ to ~/.config/fabric/patterns/ (packages.nix)
#   4. Optionally starts the fabric REST API as a macOS LaunchAgent (launchd.nix)
#
# Fabric connects to the local MLX stack by default via the Ollama-compatible
# endpoint from services.aiStack.localRouterUrl. Cloud providers (OpenAI, Anthropic,
# Gemini, etc.) work but require API keys in ~/.config/fabric/.env.
#
# Related docs:
#   - Upstream: https://github.com/danielmiessler/fabric
#   - Patterns: https://github.com/danielmiessler/fabric/tree/main/data/patterns
#
{
  config,
  pkgs,
  fabric-src,
  ...
}:
let
  cfg = config.programs.fabric;

  fabricPkg = pkgs.callPackage ./package.nix {
    inherit fabric-src;
  };
in
{
  imports = [
    ./options.nix
    ./packages.nix
    ./launchd.nix
  ];

  # Share cfg and the built package with sub-modules via _module.args
  _module.args.fabricShared = {
    inherit cfg fabricPkg;
  };
}
