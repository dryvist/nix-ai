#
# MLX Module — the GPU WIRED budget a rank start must fit under.
#
# Sibling of ./options-cluster-memory.nix, which owns the FREE-memory budget.
# Split rather than appended for the usual reason (per-file size cap), but the
# two really are different questions: free memory says whether the shard's
# ordinary resident pages fit, this says whether its wired demand fits under
# iogpu.wired_limit_mb with the compositor's own draw left standing. The option
# path is unchanged (programs.mlx.clusterMode.*). Only `lib` is referenced.
#
{ lib, ... }:
{
  options.programs.mlx.clusterMode = {
    compositorReserveMb = lib.mkOption {
      type = lib.types.int;
      default = 16384;
      description = ''
        GPU-wired memory (MB) held back from the rank-start budget for
        WindowServer and the rest of the compositor. wired_ceiling_room_ok
        (cluster-link-guards.sh) refuses a rank start unless

          current wired + shardMemoryMb <= iogpu.wired_limit_mb - this

        Inert when shardMemoryMb is 0; 0 here disables it independently.

        WHY THE CEILING ALONE IS NOT THE BUDGET. The compositor draws from the
        same wired pool and can be starved of command buffers before the
        ceiling itself is reached, taking the host down with it. The naive
        gate `wired + shard <= ceiling` computes
        47104 + 51200 = 98304 MB against 102400 and PERMITS a start that
        starves it: a false green. The ceiling reserves the compositor nothing
        (osReserveGb reserves ordinary RAM, not GPU-wired pages), so the budget
        has to be the ceiling less an explicit reserve.

        16384 (16 GiB) IS PROVISIONAL, NOT MEASURED. What is known bounds it
        only loosely: observed starvation puts the floor above 8.7 GiB, and a
        second, weaker observation above 3.3 GiB. WindowServer's own process
        footprint is around 0.9 GiB, which is NOT its GPU-wired demand and must
        not be used as the floor. 16384 is the strongest observed bound roughly
        doubled — a lower bound is not a floor — and it still leaves an
        86016 MB start budget, i.e. a 51200 MB shard onto a host already
        holding up to 34816 MB wired. For scale, a workstation holds around
        12754 MB wired while serving two standalone models.

        THE MEASUREMENT THAT WOULD REFINE IT: the compositor's actual GPU-wired
        demand under a healthy ~50 GiB serving session, sampled over a real
        interactive workload (powermetrics / footprint). Until that exists,
        raising this trades permitted starts for panic margin and lowering it
        does the reverse; do not change it on an estimate.

        RAISING IT IS NOT FREE. Every MB here is an MB a legitimate start may
        not use. Too high and a host that can serve refuses to; the refusal
        message names the arithmetic so a wrong value is diagnosable rather
        than mysterious.
      '';
    };
  };
}
