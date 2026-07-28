# Which shell layers each cluster script is assembled from.
#
# Split out of ./cluster-mode.nix at the per-file byte cap, the same seam as
# ./cluster-rank-args.nix and ./cluster-cli-env.nix. It earns its own file for a
# second reason too: the layer sets below are a DESIGN CONSTRAINT, not an
# implementation detail, and reading them side by side is the only way to see it.
#
# EVERY CONSUMER GETS EXACTLY THE LAYERS IT CALLS, and that is enforced, not
# aspirational. writeShellApplication runs shellcheck at default severity, where
# a function shipped to a script that never invokes it fails the build as SC2329.
# So the split of these libraries is driven by real call graphs rather than by
# taste, and a grab-bag "utils" layer cannot be added without immediately
# breaking every consumer that does not use all of it.
#
# The RDMA protection-domain split in particular is a privilege boundary, not
# just a size one:
#
#   cluster-pd-ledger.sh   READ side  — watcher, join, detach
#   cluster-pd-record.sh   WRITE side — watcher, detach only
#
# cluster-join reads the ledger so it can REFUSE at the cap, and is deliberately
# denied the write side: a command whose only job is to refuse must not also be
# able to spend a protection domain. Likewise the peer-liveness supervisor gets
# boot scoping (its halt marker is stamped with it) and no ledger at all.
#
# Order matters — these are concatenated, not sourced, so a definition must
# appear before the layer that calls it. Boot scope is always first.
{
  # Link watcher: the full state machine. It reads the ledger to halt before
  # exhaustion and writes to it when its own PD guard proves domains were lost.
  watcher = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-pd-ledger.sh
    ./scripts/cluster-pd-record.sh
    ./scripts/cluster-link-helpers.sh
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-link-repair.sh
    ./scripts/cluster-rank-status.sh
    ./scripts/cluster-rank-reap.sh
    ./scripts/cluster-link-guards.sh
    ./scripts/cluster-link-watcher.sh
  ];

  # Peer-liveness supervisor: the same helpers the watcher uses, so its teardown
  # is byte-identical rather than a second, drifting copy.
  peerLiveness = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-link-helpers.sh
    ./scripts/cluster-peer-observe.sh
    ./scripts/cluster-peer-liveness.sh
  ];

  # cluster-join: reads the ledger, and never reaps — the watcher owns rank
  # starts, so join has no business stopping a rank.
  #
  # It now gets the WRITE side too, and the reason is narrow: join resets the
  # kickstart counter, and that counter can be holding attempts whose leaked
  # domains are not yet in the ledger. The old rule ("a command that can only
  # refuse cannot also spend") described the reap, and it still holds there —
  # but discarding unrecorded debt IS spending, silently, which is the one thing
  # the ledger exists to prevent. Join may only settle a count it did not
  # create; it never records a fresh leak of its own.
  join = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-pd-ledger.sh
    ./scripts/cluster-pd-record.sh
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-link-repair.sh
    ./scripts/cluster-rank-status.sh
    ./scripts/cluster-join.sh
  ];

  # cluster-detach: the one command allowed to escalate to SIGKILL, so it gets
  # the graceful reap it must try first AND the write side it must pay with.
  detach = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-pd-ledger.sh
    ./scripts/cluster-pd-record.sh
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-rank-status.sh
    ./scripts/cluster-rank-reap.sh
    ./scripts/cluster-detach.sh
  ];
}
