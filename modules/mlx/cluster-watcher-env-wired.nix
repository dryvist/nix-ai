#
# The GPU wired-ceiling room guard's watcher environment.
#
# Split out of ./cluster-watcher-env.nix, which is at the per-file size cap —
# same split-rather-than-exempt pattern as ./cluster-watcher-env-peer.nix and
# ./cluster-watcher-env-ticks.nix. Merged back into the same attrset there, so
# the variables reach the watcher exactly as if they were declared inline.
#
{ ncfg }:
{
  # Wired memory held back for the compositor, making the rank-start gate
  # `wired + shard <= iogpu.wired_limit_mb - this` rather than the naive
  # `<= ceiling`, which permits a start that starves the compositor and takes
  # the host down with it. Inert when
  # shardMemoryMb is 0; 0 here disables the rung independently. Why 16 GiB and
  # what measurement would refine it: ./options-cluster-wired-room.nix. The
  # rung itself: wired_ceiling_room_ok in scripts/cluster-link-guards.sh.
  CLUSTER_COMPOSITOR_RESERVE_MB = toString ncfg.compositorReserveMb;
  # The ceiling is read LIVE from the kernel, never taken from
  # CLUSTER_WIRED_LIMIT_MB: that value is what the module MEANT to apply, and
  # a missing sudoers grant is exactly how a guard here has gone silently
  # inert before. Absolute path plus a variable seam, like CLUSTER_VMSTAT_BIN
  # — a sysctl off a sanitized PATH already disabled the halt marker once.
  CLUSTER_SYSCTL_BIN = "/usr/sbin/sysctl";
}
