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
#   cluster-pd-record.sh   WRITE side — watcher, join, detach
#   cluster-pd-settle.sh   COUNTER-SETTLE — watcher, join and detach (detach
#                          gained it when it started clearing the session's
#                          kickstart budget on exit; see the detach set below)
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
    # The CROSS-BOOT, cause-keyed read. Watcher-only: it exists to decide
    # whether to spend another domain, and the watcher is the only consumer that
    # makes that decision. join refuses at the boot-scoped cap and detach only
    # records, so neither could call it — and SC2329 turns that into a build
    # failure rather than dead code.
    ./scripts/cluster-pd-cause.sh
    ./scripts/cluster-pd-record.sh
    # jaccl Stage-A/Stage-B classifier. Ahead of cluster-pd-settle.sh, which
    # calls it, and of cluster-link-guards.sh below, whose fast_fail_standdown
    # also does — see that file's own header for why it is its own layer
    # rather than living in either consumer.
    ./scripts/cluster-pd-stage.sh
    ./scripts/cluster-pd-settle.sh
    ./scripts/cluster-link-helpers.sh
    ./scripts/cluster-serving-restore.sh
    ./scripts/cluster-peer-probe.sh
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-link-repair.sh
    ./scripts/cluster-generation-parity.sh
    ./scripts/cluster-link-facts.sh
    ./scripts/cluster-rank-status.sh
    ./scripts/cluster-rank-reap.sh
    # RULE 2's automatic key: the detached generation heal. Watcher-only — the
    # supervised heal in cluster-join stays in cluster-join.sh itself. After
    # rank-status because it refuses to touch a machine whose rank is running.
    ./scripts/cluster-generation-heal.sh
    ./scripts/cluster-link-guards.sh
    # Automated rank health gate + soak — reads mem_stat_mb from the guards
    # file above, so it must come after it.
    ./scripts/cluster-health-gate.sh
    # The peer-armed handshake. After cluster-pd-ledger.sh and
    # cluster-pd-cause.sh, whose pd_debt_count / pd_cause_budget_ok it calls —
    # a definition must precede the layer that calls it. It no longer reads
    # anything from the guards layer: the mem_headroom_ok fold was removed from
    # peer_state_write (see that function's comment). Watcher-only for the same
    # SC2329 reason as cluster-pd-cause.sh above: nothing else publishes or
    # reads peer state.
    ./scripts/cluster-peer-state.sh
    # new_progress_lines, for the soak probe's proof-of-life check ahead of
    # endpoint_busy — the same file cluster-peer-liveness.sh already pulls in.
    ./scripts/cluster-peer-observe.sh
    ./scripts/cluster-link-watcher.sh
  ];

  # The peer-state responder. NO shared layers at all, and that is the design
  # rather than an omission: it computes nothing and reads no marker, it cats the
  # file the watcher publishes. Every fact on the wire is therefore derived once,
  # by the code that also acts on it locally, so the two hosts cannot come to
  # different conclusions about what "armed" means.
  peerState = [
    ./scripts/cluster-peer-state-serve.sh
  ];

  # Peer-liveness supervisor: the same helpers the watcher uses, so its teardown
  # is byte-identical rather than a second, drifting copy.
  peerLiveness = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-link-helpers.sh
    ./scripts/cluster-serving-restore.sh
    ./scripts/cluster-peer-probe.sh
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
    # See the watcher set above for why this is its own layer.
    ./scripts/cluster-pd-stage.sh
    ./scripts/cluster-pd-settle.sh
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-link-repair.sh
    ./scripts/cluster-generation-parity.sh
    ./scripts/cluster-peer-probe.sh
    ./scripts/cluster-join-preflight.sh
    ./scripts/cluster-rank-status.sh
    # join QUIESCES standalone serving, so it must be able to give it back when
    # it does not end in a formed cluster — the same single definition the
    # watcher and detach use, never a fourth partial copy. See the EXIT trap in
    # cluster-join.sh.
    ./scripts/cluster-serving-restore.sh
    ./scripts/cluster-join.sh
  ];

  # cluster-detach: the one command allowed to escalate to SIGKILL, so it gets
  # the graceful reap it must try first AND the write side it must pay with.
  #
  # It also gets ./scripts/cluster-serving-restore.sh, and that is a correctness
  # fix rather than tidying: detach used to carry a coordinator-only copy of half
  # the restore and no worker path at all, so on a worker it reported "teardown
  # verified" and exit 0 over a host that was serving nothing (2026-08-01, 86h).
  # Every path that claims to restore serving now runs the same function.
  detach = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-pd-ledger.sh
    ./scripts/cluster-pd-record.sh
    # Detach DOES reset a counter now, so the note above ("detach resets no
    # counter") no longer holds for it: it clears the session's kickstart budget
    # on both its exits, so a failed detach cannot leave the next session
    # part-spent. Settling rather than deleting is what keeps that from
    # laundering attempts whose domains are not yet on the ledger.
    # See the watcher set above for why this is its own layer.
    ./scripts/cluster-pd-stage.sh
    ./scripts/cluster-pd-settle.sh
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-serving-restore.sh
    ./scripts/cluster-rank-status.sh
    ./scripts/cluster-rank-reap.sh
    ./scripts/cluster-detach.sh
  ];
}
