#
# MLX Module — cluster-join / cluster-detach lifecycle-command tunables
#
# Split out of ./options-cluster.nix (itself split out of ./cluster-mode.nix)
# purely to keep each file under the repo per-file size cap. The option paths
# are UNCHANGED (programs.mlx.clusterMode.*): the module system merges this
# declaration block with the ones in options-cluster.nix, cluster-mode.nix, and
# cluster-mode-maintenance.nix. Only `lib` is referenced here.
#
{ lib, ... }:
{
  options.programs.mlx.clusterMode = {
    generationRepo = lib.mkOption {
      type = lib.types.str;
      default = "dryvist/nix-darwin";
      description = ''
        GitHub owner/repo whose origin/main is the deploy source of truth for
        the cluster-join generation-parity preflight: every node must run a
        system generation stamped with that branch's HEAD revision before any
        clustering config begins (two nodes both at remote HEAD are identical
        by construction). Drift auto-heals by rebuilding directly from the
        remote flake ref (github:<repo>/<rev>) — no local checkout is
        referenced. Empty string disables the preflight.
      '';
    };

    joinSwapThresholdMb = lib.mkOption {
      type = lib.types.int;
      default = 8000;
      description = ''
        cluster-join refuses to load a shard when vm.swapusage used exceeds this
        (MB). Loading a shard against stale swap spirals to a panic (INC-17075);
        the operator is told to reboot first.
      '';
    };

    detachSwapThresholdMb = lib.mkOption {
      type = lib.types.int;
      default = 20000;
      description = ''
        cluster-detach exits with a distinct code (3) and a prominent
        reboot-before-next-join warning when vm.swapusage used exceeds this (MB),
        so a wrapper can chain a reboot.
      '';
    };

    joinTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 600;
      description = "cluster-join bound (s) on the block-until-a-real-generation wait.";
    };

    detachTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "cluster-detach bound (s) on the teardown and standalone-serving-restore waits.";
    };

    quiesceGraceSecs = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "cluster-join grace (s) for standalone-serve engines to exit before orphans are reaped.";
    };

    workerStableSecs = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "cluster-join (worker role) seconds the rank must stay up to be declared stable.";
    };

    keepResidentBackends = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--port 11442" ];
      description = ''
        Command-line substrings identifying standalone-serving `vllm-mlx serve`
        backends the coordinator cluster-join must NOT reap when it quiesces for
        the shard. A process whose command line contains any of these is left
        running so it survives the cluster window — e.g. a standalone brain
        agent on its own gated port kept resident for cluster-window
        availability. The whole-llama-swap bootout is unchanged (it is the panic
        guard); this only spares matching standalone engines from the
        `vllm-mlx serve` reap and the zero-engine assert. Empty = quiesce every
        engine (the panic-safe default). Only exempt a backend whose wired
        footprint provably fits under the cluster wired ceiling ALONGSIDE the
        shard — a resident co-loaded over the ceiling is the INC-17076 panic.
      '';
    };
  };
}
