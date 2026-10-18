#
# MLX Module — cluster-join / cluster-detach lifecycle-command tunables
#
# Split out of ./options-cluster.nix (itself split out of ./cluster-mode.nix)
# purely to keep each file under the repo per-file size cap. The option paths
# are UNCHANGED (programs.mlx.clusterMode.*): the module system merges this
# declaration block with the ones in options-cluster.nix and cluster-mode.nix.
# Only `lib` is referenced here.
#
{ lib, ... }:
{
  options.programs.mlx.clusterMode = {
    generationRepo = lib.mkOption {
      type = lib.types.str;
      default = "dryvist/nix-darwin";
      visible = false;
      description = "Removed compatibility shim; ignored by cluster lifecycle commands.";
    };

    hostGeneration = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Consumer's nix-darwin revision, compared with the peer before either rank starts.";
    };

    peerSsh = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "user@host";
      description = "Optional SSH destination for the coordinator to drive worker join and detach.";
    };

    pdReserve = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "RDMA protection domains held in reserve after a rank start.";
    };

    quiesce.apps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Application bundle identifiers whose launchd application jobs are booted out before the room check.";
    };

    quiesce.launchdLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Launchd labels booted out before the room check and restored by cluster-detach.";
    };

    joinSwapThresholdMb = lib.mkOption {
      type = lib.types.int;
      default = 8000;
      description = ''
        cluster-join refuses to load a shard when vm.swapusage used exceeds this
        (MB). Loading a shard against stale swap spirals to a panic; the
        operator is told to reboot first.
      '';
    };

    standaloneLeaseSecs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7200;
      description = ''
        Default duration (s) of the standalone lease cluster-detach records —
        the ONE sanctioned way to hold a plugged-in machine out of the cluster
        (RULE 1: plugged in means clustered). While the lease is unexpired the
        watcher leaves the machine standalone; at expiry it re-admin-ups the
        detached Thunderbolt port and drives the pair back to clustered,
        unattended. Overridable per call (`cluster-detach <secs> [reason]`);
        cluster-join ends a lease early. Deliberately no indefinite form: an
        opt-out that cannot expire is detached-while-plugged with extra steps —
        the exact stable waste state the rule exists to end.
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
        shard — a resident co-loaded over the ceiling panics the host.
      '';
    };
  };
}
