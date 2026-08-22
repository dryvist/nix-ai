#
# MLX Module — clustered-mode peer-state handshake tunables
#
# Split out of ./options-cluster.nix purely to keep each file under the repo
# per-file size cap. The option paths are UNCHANGED
# (programs.mlx.clusterMode.*): the module system merges this block with
# options-cluster.nix, options-cluster-resilience.nix,
# options-cluster-rank-health.nix, options-cluster-memory.nix and the rest.
#
# The seam is real. Every other cluster option tunes what THIS host does about
# what it can see for itself. These four exist because a host could not see the
# one thing that decided whether spending an RDMA protection domain was worth
# anything: whether the machine on the other end of the cable was in any state
# to answer. See ./scripts/cluster-peer-state.sh.
#
{ config, lib, ... }:
{
  options.programs.mlx.clusterMode = {
    peerStateFile = lib.mkOption {
      type = lib.types.str;
      internal = true;
      readOnly = true;
      default = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/peer-state.json";
      description = ''
        Where the link watcher publishes this host's state and the responder
        reads it back. An option rather than a let-binding for one reason: the
        writer and the reader live in different modules, and a path each side
        derives for itself is a writer and a reader on different files. Same
        rule the protection-domain ledger path already follows.

        Not a marker. Nothing in the teardown clears it, because a stale
        publication is not cleared by deleting it — the ts field is what makes
        an old state refusable, and a missing file would read as "unreachable"
        rather than "not armed", which is a weaker and less accurate answer.
      '';
    };

    peerStatePort = lib.mkOption {
      type = lib.types.port;
      default = 11442;
      description = ''
        Port each host serves its own cluster state on, bound ONLY to that
        host's static Thunderbolt link address. The peer's link watcher reads it
        before every rank start and refuses to start unless the answer says the
        peer is armed, has memory headroom, and is running the same system
        generation.

        Sits beside the rendezvous port (11441) on purpose: the two are the only
        ports that exist on the cable itself, and keeping them adjacent keeps
        the whole cross-host surface legible in one line of `netstat`.

        0 disables the handshake entirely — every gate that reads it passes, and
        rank starts fall back to the ICMP-only peer probe. That is the behaviour
        that spent five of eleven protection domains in eighteen minutes on
        2026-08-08 against a peer that had already stood down, so 0 is an escape
        hatch for a rollout, not a supported steady state.
      '';
    };

    peerStateTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = ''
        Bound on one peer-state fetch. Short by design: the request travels one
        Thunderbolt hop to a responder that does nothing but cat a file, so
        anything slower than this is a host in trouble rather than a slow
        answer — and the fetch happens inside a watcher tick that has other work
        to do. A timeout reads as "peer unreachable", which suppresses the start
        at a cost of zero protection domains, so erring short is the safe
        direction.
      '';
    };

    peerStateStaleTicks = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = ''
        How many watcher ticks old a fetched peer state may be before it is
        refused. Converted to seconds against tickIntervalSecs, so the two
        numbers cannot drift apart.

        THIS IS THE GUARD AGAINST A DEAD WATCHER GRANTING PERMISSION. The
        responder serves whatever file is on disk and knows nothing about
        whether the watcher that writes it is still alive — so a host whose
        watcher died would otherwise keep answering armed=true from its last
        healthy tick, indefinitely, having no ability to rendezvous.

        IT MUST ALSO EXCEED THE WATCHER'S OWN SLOWEST TICK. That is the
        subtlety that made this 3 and made clustering impossible. The publish
        happens near the top of a tick, and the rank-start boundary SLEEPS
        inside that same tick, up to rankStartAlignMultiple ticks long. So the
        gap between two publishes is a tick plus the alignment hold plus the
        probes — never a single tick. At 3 (90s against a 30s tick and a 60s
        hold) the window equalled the hold plus one tick, leaving nothing over
        to cover the probes: measured 2026-08-16, both hosts published every
        95-173s, so each read the other as stale and suppressed every start.
        Both were armed, both were healthy, and the cluster could never form.

        8 leaves real margin above tickIntervalSecs * (rankStartAlignMultiple
        + 1) and still catches a genuinely dead watcher inside four minutes.
        The relationship is asserted in cluster-assertions.nix, never left to
        this comment alone.
      '';
    };

    pdCauseBudget = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        RDMA protection domains one halt CAUSE may consume across ALL boots
        before this host refuses to start a rank for that reason again. 0
        disables the cross-boot axis.

        WHY A SECOND BUDGET WHEN maxKickstarts ALREADY EXISTS. That one is
        boot-scoped, which is correct — a reboot returns every leaked domain, so
        a reboot must clear the ledger. It is also the escape hatch a repeating
        defect uses: leak five, reboot, leak five again, with every boot
        starting from a full budget and every guard reading green. Two of those
        nights happened a day apart.

        IT SHOULD NEVER FIRE. With the peer-armed handshake in place a start
        against a peer that cannot rendezvous costs zero domains, so a cause
        that reaches this budget is evidence the handshake itself is broken —
        which is exactly the situation where a human should be the next step
        rather than another automatic retry.

        Consequently the reset is evidence-gated: not a reboot, not a link
        cycle, not a marker delete. Two things clear a bucket. The watcher
        settles it automatically when this host completes a formation, passes
        the health gate and then passes a periodic soak probe — a cluster that
        is serving is the evidence the budget was holding out for. Failing
        that, an operator appends an entry with source=cause-budget-reset to
        the protection-domain ledger, which is a written statement that
        somebody looked. Either way the history lines stay; only the running
        total is cleared.
      '';
    };
  };
}
