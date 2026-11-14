# Frozen SHA-256 digests of builtins.toJSON over the projection in
# mcp-facade-default-off-projection.nix, freshly compared from base bd39621a
# and the candidate with the same locked inputs. The only changed input is
# homelab-contracts v5.19.2 at de3be0f0; nixpkgs is 752cbac9 and home-manager
# is 24f21905. The Home Manager assertions and projections were deepSeq'd for
# both systems before comparing. These values match the earlier 37b952fc
# baseline, now verified at the exact source base for this candidate.
# flakeLockSha256 and both projection digests track the all non-major dependencies
# update in #2855: its MCP server version bumps change store paths in the
# projection; byte counts are unchanged.
{
  baseCommit = "bd39621af5358bf01af73899f1761430ec6fae3d";
  flakeLockSha256 = "11dfb0e3d505d0b9f267959088de46177566a4d218ed4fe17d457c2eb3348e22";
  projections = {
    aarch64-darwin = {
      bytes = 3357;
      sha256 = "de5ca3d56fd484c910b6f9348625c887f29cf98487280f95af4afd9ce7317352";
    };
    x86_64-linux = {
      bytes = 3175;
      sha256 = "cd493162676eae7b9017a71136e811230ba1ec84d0738aab0fae074c80dde0de";
    };
  };
}
