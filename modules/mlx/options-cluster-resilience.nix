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

    rankStartAlignMultiple = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = ''
        Multiple of tickIntervalSecs giving the shared wall-clock start boundary
        for BOTH ranks, exported as CLUSTER_RANK_START_ALIGN_SECS. Must be at
        least 2; see the cluster-link-guards notes for why the period must
        exceed the tick and why both ranks start together instead of the worker
        waiting for rank 0.
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
      default = "/bin/bash";
      description = ''
        Interpreter the shell-only cluster agents are launched with. null uses
        each script's own Nix shebang.

        This exists because of how macOS grants network access. TCC keys a
        privacy grant to a binary's CODE-SIGNING IDENTITY, and a Nix binary's
        identity IS its content hash:

          nix bash:    designated => cdhash H"51837d11..."
          Apple bash:  designated => identifier "com.apple.bash" and anchor apple

        So every nixpkgs bump mints an executable macOS has never seen and the
        previous Local Network grant becomes inert. Worse, no wrapper launders
        it: a Nix binary anywhere in the chain becomes the responsible process
        for everything below it, which is why even Apple's own /sbin/ping is
        denied when its parent is a Nix bash (all measured 2026-07-25).

        Launching under Apple's /bin/bash makes the ENTIRE chain Apple-signed,
        so these agents need no Local Network grant at all — not one that
        expires, not one at all. Verified on jevans-mbp: the same ping that
        returns "No route to host" under the Nix shebang returns rc=0 from a
        launchd job under /bin/bash.

        Safe because the shell agents are self-contained and conservative:
        their helpers are concatenated in at build time (no runtime `source`),
        they carry no bash-5-only constructs, and both parse cleanly under the
        bash 3.2 Apple ships. That is checked, not assumed — see
        lib/checks/mlx-cluster-scripts.nix.

        Does NOT cover the rank: it execs a Python interpreter, which becomes
        its own responsible process. That one needs a stable code-signing
        identity instead (dryvist/nix-darwin#1890).

        Set to null only if a script ever genuinely needs bash 5 — and then fix
        the script, because this is what keeps the cluster self-forming.
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
