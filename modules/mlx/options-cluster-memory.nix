#
# MLX Module — clustered-mode memory-headroom tunables (does this shard FIT?)
#
# Split out of ./options-cluster-rank-health.nix purely to keep each file under
# the repo per-file size cap. The option paths are UNCHANGED
# (programs.mlx.clusterMode.*): the module system merges this block with the
# ones in options-cluster.nix, options-cluster-resilience.nix,
# options-cluster-rank-health.nix, cluster-mode.nix and
# cluster-mode-maintenance.nix. Only `lib` is referenced.
#
{ lib, ... }:
{
  options.programs.mlx.clusterMode = {
    shardMemoryMb = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        Expected per-rank working set (MB) once the cluster shard is loaded.
        rank_start_preconditions_ok refuses a rank start unless free +
        reclaimable memory (vm_stat "Pages free" + "Pages inactive" +
        "Pages speculative") reports at least this much — measured against
        FREE memory, never wired: MLX holds a loaded shard's weights in
        ordinary resident memory, not wired (measured 2026-08-01, a ~49 GiB
        shard served real tokens while `Pages wired down` read only ~3.5 GiB).

        0 (default) disables the rung cleanly: no vm_stat read, no refusal.
        There is no safe universal default — the right value is the deployed
        model's shard size on THIS host — so it is opt-in per cluster config,
        same as wiredLimitMb above.

        WHY THIS RUNG EXISTS. On 2026-08-01 a rank started while ~72 GiB of
        unreclaimed wired Metal memory sat on the host from previously-crashed
        rank processes, left only ~25 GiB free against a ~49 GiB shard, and
        died `[METAL] Command buffer execution failed: Insufficient Memory`.
        That failed distributed init still leaked an RDMA protection domain —
        the same reboot-only resource devicePdBudget/maxKickstarts protect —
        and the same chain then repeated four more times and hit the cap. This
        rung stops it before the first attempt: a precondition that is not yet
        met costs no attempt (see rank_start_preconditions_ok), so refusing
        here is free in the currency that guard actually protects.
      '';
    };

    wiredCeilingMb = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        Runtime ceiling (MB) on the "Pages wired down" figure of a RUNNING
        rank. Above it the watcher reaps the rank and restores standalone
        serving. 0 (default) disables the guard with no vm_stat read at all,
        same convention as shardMemoryMb above.

        WHY A RUNTIME GUARD, GIVEN shardMemoryMb ALREADY GATES THE START. That
        rung is a precondition: it runs only ahead of a start, and asks whether
        FREE memory fits a shard. Neither property helps once a rank is up. On
        2026-08-01 a rank started legally, and wired later climbed to 96.7 GiB
        against this host's 100 GiB iogpu.wired_limit_mb. WindowServer asked
        Metal to hand over a command buffer, got nothing, and blocked inside the
        GPU driver (IOGPUFamily, AGXG16X) 80 seconds; watchdogd killed it, and
        the hardware watchdog hard-reset the machine, recording the boot fault
        "wdog,reset_in_1". Every existing rung stayed green throughout, having
        already run. The compositor competes over the same wired GPU budget as
        the shard, so a rank may take most of that budget but never all of it.

        HOW HIGH TO SET IT. A healthy serving rank wires approximately its
        WHOLE shard. Two independent captures agree within 2.3%: the REALVMSTAT
        fixture in tests/test-mem-headroom.sh (a byte-for-byte real capture)
        reads 3348211 pages, ~51.1 GiB, and nix-darwin's
        hosts/common/cluster-wired-limit.nix recorded 3271199 pages, ~49.9 GiB,
        with both ranks serving. An earlier note in cluster-link-guards.sh
        claiming ~3.5 GiB was RETRACTED 2026-08-01 as a bad measurement, ~15x
        adrift of both captures.

        So set it clear of ONE shard, never near it: a ceiling below one shard
        reaps every healthy rank on sight, which is far worse than a ceiling
        set somewhat high. The 2026-08-01 hang read 96.7 GiB, close to two
        shards and consistent with a second rank or a leaked predecessor, so a
        ceiling placed between one shard and two separates healthy from
        dangerous.

        SET IT BELOW THE WIRED CEILING, NOT NEAR IT. What matters is the margin
        left to the compositor, so derive this from
        clusterLinkPrep.clusterWiredLimitMb (the iogpu ceiling actually applied
        to the host), never from shard size. No safe universal default exists —
        the ceiling is per-host — so this stays opt-in, exactly like
        shardMemoryMb and wiredLimitMb.
      '';
    };

    memHeadroomHaltSecs = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = ''
        How long the memory-headroom rung must refuse CONSECUTIVELY before the
        watcher escalates from a per-tick skip to a HALT (converted to
        CLUSTER_MEM_HEADROOM_DWELL_TICKS against tickIntervalSecs, same ceil
        derivation as linkDownSettleSecs). Ignored when shardMemoryMb is 0.

        WHY A HALT AT ALL, RATHER THAN SKIPPING FOREVER. A precondition skip
        is deliberately free and silent — see shardMemoryMb above — which is
        correct for a shortfall that clears on its own. But the 2026-08-01
        shortfall was unreclaimed wired Metal memory, which is boot-scoped and
        does NOT clear on its own; left as a bare skip that shape is
        invisible, and the host never clusters even with the Thunderbolt cable
        plugged in the whole time — the "plugged in but not clustered" state
        the operator's chaos-monkey doctrine rules out. So a shortfall that
        holds this long escalates to a halt, which puts it in front of
        pd_auto_reboot_if_warranted exactly as pd-debt-exhausted and
        rank-start-failures already are (see cluster-link-guards.sh).

        A HALT IS NOT A GUARANTEE THE REBOOT FIXES IT. Unlike the PD ledger,
        a low-memory shortfall is not always the boot-scoped leak signature —
        it could be some other process legitimately holding memory, which a
        reboot may or may not resolve. The dwell exists to tell "genuinely
        stuck" from "transient" apart; pd_auto_reboot_if_warranted's own rate
        limit is what keeps a reboot that does not help from repeating without
        bound.

        300s (5 min at the 30s default tick) is a starting guess, not a
        measurement, same caveat as pdAutoRebootWindowSecs: long enough that an
        ordinary transient (another process briefly busy) clears on its own,
        short enough that a genuinely stuck host does not sit refusing for
        hours before anything escalates.
      '';
    };
  };
}
