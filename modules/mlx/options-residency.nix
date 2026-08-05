#
# MLX Module — Residency budget options
#
# The three options here are one interlocking set, which is why they live apart
# from the rest of the runtime options: they are the only knobs that decide how
# much memory may be held resident, and changing any one of them without the
# others breaks the invariant
#
#   maxResidentWorkers * memoryHardLimitGb <= host wired ceiling
#
# The ceiling is the host sysctl iogpu.wired_limit_mb (nix-darwin
# appleSiliconTunables), which nothing in this repo sets. See
# modules/mlx/options-runtime.nix for the surrounding memory-safety layering.
#
{ lib, ... }:
{
  options.programs.mlx = {
    memoryHardLimitGb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 99;
      description = ''
        L2 process memory limit in GiB, enforced in-process before serving via
        mx.set_memory_limit in the mlx_lm launcher (scripts/mlx-lm-launch.py).
        A guideline in MLX terms — it forces cache shedding and allocation
        failure ahead of the host wired ceiling (L1, iogpu.wired_limit_mb)
        rather than at MLX's 1.5x-working-set default, so memory pressure
        surfaces as an application error instead of host-wide swap. Set below
        the wired ceiling with a small cushion (99 GiB under the 100 GiB /
        102400 MiB ceiling on the 128 GiB Macs).
      '';
    };

    maxResidentWorkers = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        How many model workers may hold weights at once (k_max). This is the
        free variable in the memory invariant

          maxResidentWorkers * memoryHardLimitGb <= host wired ceiling

        and it is enforced structurally by the llama-swap group topology rather
        than by any per-process limit, because mx.set_memory_limit is a
        guideline that refuses nothing.

        1 (default) collapses every model into a single exclusive group, so
        loading any model evicts the previous one. That satisfies the invariant
        at the existing memoryHardLimitGb with no number change, at the cost of
        a model-swap reload when traffic alternates between tiers.

        Above 1 restores the tiered topology, where a persistent resident and a
        non-exclusive swap tier can hold weights simultaneously. Only raise it
        together with a lowered memoryHardLimitGb so the product still fits the
        ceiling — 2 workers at the default 99 GiB permits 198 GiB against a
        100 GiB ceiling, which over-commits it.

        Clustered mode is unaffected: a rank serves one sharded model, so
        k_max is 1 there regardless.
      '';
    };

    suppressWiredLimit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Suppress the wired-limit pin mlx_lm.server applies at startup
        (ml-explore/mlx#3186, Apple FB22091885). The server calls
        mx.set_wired_limit with the full recommended working set,
        unconditionally inside main and with no flag to disable it. That pin is
        the discriminating variable for an IOGPUFamily "completeMemory prepare
        count underflow" kernel panic — upstream isolated it single-variable at
        roughly 100 seconds to panic under prompt-cache eviction churn with the
        call, versus about 9 hours and 5.3M tokens clean without it. Reproduced
        on M3 Ultra, M4 Max, M4 Pro, M4 and M5 Air, so it is not
        capacity-specific.

        Note mx.set_wired_limit PINS memory resident; it is not a cap. The real
        ceiling stays the host sysctl iogpu.wired_limit_mb. Suppressing leaves
        MLX at its default of zero (nothing pinned), so weights become pageable
        and throughput degrades under external memory pressure — costed upstream
        at under 3 percent on sequential work. That makes the residency budget
        load bearing: k_max times memoryHardLimitGb must stay under the wired
        ceiling, or this trades a kernel panic for swap thrash.

        Passes the MLX_SUPPRESS_WIRED_LIMIT marker to
        scripts/mlx-lm-launch.py, which fails closed if the upstream call site
        changes shape rather than silently no longer intercepting. Turn off once
        upstream ships a fix.
      '';
    };
  };
}
