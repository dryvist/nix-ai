# Frozen SHA-256 digests of builtins.toJSON over the projection in
# mcp-facade-default-off-projection.nix, freshly compared from base bd39621a
# and the candidate with the same locked inputs. The only changed input is
# homelab-contracts v5.19.2 at de3be0f0; nixpkgs is 752cbac9 and home-manager
# is 24f21905. The Home Manager assertions and projections were deepSeq'd for
# both systems before comparing. These values match the earlier 37b952fc
# baseline, now verified at the exact source base for this candidate.
# flakeLockSha256 and both projection digests track the all non-major dependencies
# update in #2855: its MCP server version bumps change store paths in the
# projection; byte counts are unchanged. Both projection digests track the
# mcp-server-time 2026.11.4 bump in #3010: its shorter version string changes
# the store path and removes one byte on each system.
{
  baseCommit = "bd39621af5358bf01af73899f1761430ec6fae3d";
  flakeLockSha256 = "1d5970284916cc2d6384aff51e5b1b9c0e06d7f85a367dbe518b4afe9a662766";
  projections = {
    aarch64-darwin = {
      bytes = 3356;
      sha256 = "353e6b96da6068d13a94452c139b80df7dc907de03cf2be905e7998a3f55bfb9";
    };
    x86_64-linux = {
      bytes = 3174;
      sha256 = "edfe30ef1c10de4a00e0082724f466dbf4f138d772ed42ea67524b5115c701c1";
    };
  };
}
