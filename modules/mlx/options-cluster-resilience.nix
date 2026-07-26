#
# MLX Module — clustered-mode resilience tunables (unattended bring-up/teardown)
#
# Split out of ./options-cluster.nix (itself split out of ./cluster-mode.nix)
# purely to keep each file under the repo per-file size cap. The option paths are
# UNCHANGED (programs.mlx.clusterMode.*): the module system merges this block
# with the ones in options-cluster.nix, options-cluster-lifecycle.nix,
# cluster-mode.nix and cluster-mode-maintenance.nix. Only `lib` is referenced.
#
# Everything here exists so that plugging or unplugging the cable is the ONLY
# human action a cluster bring-up requires. Each value is a threshold the
# watcher previously carried as a script default, i.e. a number nobody could see
# or change from configuration.
#
{ lib, ... }:
{
  options.programs.mlx.clusterMode = {
    tickIntervalSecs = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = ''
        Link-watcher StartInterval. This is the cluster's convergence quantum:
        every threshold below that is expressed in seconds is converted into
        ticks against THIS value, so the two can never drift apart.
      '';
    };

    linkDownSettleSecs = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = ''
        How long the link must stay unreachable before the watcher declares it
        down and tears the rank down. Converted to consecutive failed probes
        (CLUSTER_LINK_DOWN_STRIKES) against tickIntervalSecs, rounded up, floor
        of one — it does not add a second debounce, it gives the existing one a
        unit an operator can reason about.

        Debounce is deliberately ASYMMETRIC: a false "down" is destructive (it
        stops the rank AND resets the RDMA PD guard, so a flapping link could
        never accumulate toward a halt — seen 2026-07-19), while a false "up"
        only attempts a start the guard already caps. So "up" is believed on the
        first reply and "down" must be earned over this window.
      '';
    };

    peerRendezvousProbeTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = ''
        Bound on the worker's "is rank 0 listening?" TCP connect probe, which
        gates every worker rank start. Must stay well under tickIntervalSecs: a
        probe that outlives the tick is not a probe.

        A blackholed SYN is the case that needs bounding — measured 2026-07-25,
        macOS nc with `-w 2` still took 75s because Apple's nc applies -w to
        idle reads and not to connect setup, so the probe is wrapped in
        coreutils `timeout` instead.
      '';
    };

    linkRepair = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the watcher repair a MISSING local link address in place instead of
        starting a rank that cannot bind.

        A boot does not produce a usable link: nix-darwin's cluster-link prep
        runs in root postActivation, which fires before Thunderbolt carrier
        settles, so the pass can find no carrier-active port and address
        nothing. Observed 2026-07-24 — carrier present on the cabled port,
        activation completed, no interface holding the link address, and the
        rank died with `[jaccl] Couldn't bind socket (error: 49)` (errno 49 =
        EADDRNOTAVAIL). Repair uses only the existing cluster-ops sudoers
        grants and is the same idempotent aliasing the prep pass performs.

        Turning this off does NOT make the watcher start such a rank: the
        missing address remains a hard precondition. It only stops the watcher
        from fixing it.
      '';
    };

    appleInterpreter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Per-cluster override for programs.mlx.appleInterpreter. null (the
        default) inherits the module-wide value, which is where the convention
        and its rationale live — see ./options-launch.nix.

        Present only so a single host can opt one cluster agent out without
        changing the estate default. Almost nothing should set this.
      '';
    };

    linkRepairActivateTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 150;
      description = ''
        Bound on the fallback `system/activate` pass used when the direct
        granted repair does not restore the link address. 0 = never activate
        from the watcher (direct repair only).

        A full activation can wedge on an unrelated step (2026-07-19: a
        home-manager symlink hung on a stale mount), so it is bounded and tried
        second — the direct alias is the same change with a far smaller blast
        radius, which matters on a 30s tick.
      '';
    };

  };
}
