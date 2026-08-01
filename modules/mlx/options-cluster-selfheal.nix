#
# MLX Module — clustered-mode self-heal and attribution tunables
#
# Split out of ./options-cluster-resilience.nix, which was already at the
# per-file warn threshold (.file-size.yml). Option paths are UNCHANGED
# (programs.mlx.clusterMode.*): the module system merges this block with the ones
# in options-cluster.nix, options-cluster-lifecycle.nix,
# options-cluster-resilience.nix, cluster-mode.nix and
# cluster-mode-maintenance.nix. Only `lib` is referenced.
#
# WHAT THIS FILE IS FOR. On 2026-08-01 the Thunderbolt link sat down for 86 hours
# with the cable seated. Every component behaved as designed and the outage was
# invisible to all of them:
#
#   * the node had drifted off the deployed system generation, so the activation
#     that aliases the link address never ran — and the only parity check in the
#     system lived in cluster-join, which a human has to start;
#   * the watcher probed the peer, failed, and never looked at its own link prep,
#     although it already carried the repair for exactly that condition;
#   * it logged one guess ("cable out, OR denied Local Network permission")
#     10,440 times, and the truth was neither.
#
# Every value below turns one of those into something that happens on a clock.
#
{ lib, ... }:
{
  options.programs.mlx.clusterMode = {
    linkPrepMaxRepairs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        Consecutive link-prep self-heal attempts the watcher makes while a
        Thunderbolt port has carrier and this host holds no link address, before
        it stops repairing and only reports. The counter resets the instant prep
        is healthy, so a repair that works costs one attempt.

        The bound is against thrash, not against repair: the self-heal frees the
        port from bridge0 and re-aliases the address, and doing that every 30s
        for days on a link that cannot be fixed is churn, not persistence.
        Reaching the cap silences the REPAIR, never the report — the facts line
        keeps naming per-port carrier and where the address is, and any tick
        where prep is healthy again clears the count.
      '';
    };

    downReportEverySecs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = ''
        How often the watcher repeats its still-down report while the link is
        confirmed down, converted to ticks against tickIntervalSecs (rounded up,
        floor of one) so the cadence and the tick cannot drift apart.

        A change in the observed facts is ALWAYS reported immediately regardless
        of this value; the cadence only governs repetition of an unchanged state.
        That is the half that was missing: 10,440 identical lines do not report a
        state, they bury the one line where it changed.
      '';
    };

    generationCheckSecs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3600;
      description = ''
        How often the link watcher re-checks that this node is running the
        deployed system generation (generationRepo). Cached between checks, so
        the cost is one `git ls-remote` per interval rather than one per watcher
        tick, and the result is reported as a field of the link facts line in
        every link state.

        Drift is what silently disarmed link prep for 86 hours on 2026-08-01. The
        watcher reports and pages (once per distinct drift); the HEAL stays in
        cluster-join, because a `darwin-rebuild switch` fired from a launchd
        agent can be SIGKILLed mid-activation by the very activation it is
        running, and a half-applied activation is worse than drift.
      '';
    };

    peerReadyTimeoutSecs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = ''
        How long cluster-join waits for the peer to answer on the link before
        refusing, naming which side is unprepared.

        Without it, a peer that held no link address cost the full
        joinTimeoutSecs (600s) and then surfaced `[jaccl] Couldn't connect
        (error: 60)` — ETIMEDOUT, which reports that a connection did not
        complete and is structurally incapable of saying which machine was
        wrong. Short on purpose: both watchers now self-heal their own link prep
        unattended, so a peer that is merely slow answers within a tick or two,
        and one still silent after this window is unprepared rather than late.
      '';
    };
  };
}
