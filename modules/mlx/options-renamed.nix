# Renamed mlx option aliases (split out for the 12KB file-size gate).
#
# Consumers set some of these options from their own config (nix-darwin wires
# the cluster wired ceilings in from system.clusterLinkPrep), and the two repos
# move on independent flake bumps. An alias keeps a consumer pinned to the old
# name evaluating against this revision.
#
# Note this does NOT make merge order free in the other direction: a consumer
# setting the NEW name cannot evaluate against an older nix-ai. Land the rename
# here first, then bump the consumer's flake.lock, then rename the consumer.
#
# Drop each alias once every consumer is past that rename.
{ lib, ... }:
{
  imports = [
    (lib.mkRenamedOptionModule
      [
        "programs"
        "mlx"
        "clusterMode"
        "dayWiredLimitMb"
      ]
      [
        "programs"
        "mlx"
        "clusterMode"
        "standaloneWiredLimitMb"
      ]
    )
  ];
}
