# Frozen SHA-256 digests of builtins.toJSON over the projection in
# mcp-facade-default-off-projection.nix, freshly compared from base bd39621a
# and the candidate with the same locked inputs. The only changed input is
# homelab-contracts v5.19.2 at de3be0f0; nixpkgs is 752cbac9 and home-manager
# is 24f21905. The Home Manager assertions and projections were deepSeq'd for
# both systems before comparing. These values match the earlier 37b952fc
# baseline, now verified at the exact source base for this candidate.
{
  baseCommit = "bd39621af5358bf01af73899f1761430ec6fae3d";
  flakeLockSha256 = "85c688758b002ee077e6702c8e6b8f1a8c298dea144da3107dee6c0c645027fb";
  projections = {
    aarch64-darwin = {
      bytes = 3357;
      sha256 = "db25765b1dda424737ffb217c5a9ed6a4d4a92a42e993cea9b2290a6ad48fd05";
    };
    x86_64-linux = {
      bytes = 3175;
      sha256 = "cd6d5c1f4900bbd14170dfe1dc2ed74f3c564fbe3527e1e8c54d61fab406feeb";
    };
  };
}
