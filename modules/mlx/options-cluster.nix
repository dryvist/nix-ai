#
# MLX Module — Clustered-mode option declarations
#
# Split out of ./cluster-mode.nix (which keeps the let-bindings, packages,
# config wiring, and the staticLinkIps option) purely to keep each file under
# the repo per-file size cap. The option paths are UNCHANGED
# (programs.mlx.clusterMode.*): the module system merges this declaration block
# with the staticLinkIps option + config block in cluster-mode.nix and the
# agents in cluster-mode-maintenance.nix. Only `config` (for the home-directory
# default) and `lib` are referenced here.
#
{
  config,
  lib,
  ...
}:
{
  options.programs.mlx.clusterMode = {
    enable = lib.mkEnableOption "two-Mac JACCL clustered mode (mlx-lm pipeline-parallel serving)";

    role = lib.mkOption {
      type = lib.types.enum [
        "coordinator"
        "worker"
      ];
      description = "coordinator = rank 0, binds the cluster HTTP endpoint; worker = rank 1.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "mlx-community/GLM-4.7-4bit";
      description = ''
        HuggingFace id of the cluster model. Must use an architecture with
        distributed support in the pinned mlx-lm (glm4_moe: pipeline).
        198 GB weights split across both ranks via --pipeline.
      '';
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 11440;
      description = "Cluster endpoint port on the coordinator (loopback; exposed via the host's gateway).";
    };

    rendezvousPort = lib.mkOption {
      type = lib.types.port;
      default = 11441;
      description = "JACCL coordinator rendezvous port (MLX_JACCL_COORDINATOR).";
    };

    maxKickstarts = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        Consecutive failed rank starts before the watcher halts kickstarts
        and pages once. Every failed distributed init leaks a kernel RDMA
        Protection Domain and exhaustion is reboot-only (ml-explore/mlx#3207),
        so an unbounded crash loop forces a reboot.
      '';
    };

    alertUrlFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/mlx-cluster/alert-url";
      description = ''
        Untracked local file holding the notification URL (ntfy-style POST
        target) for the halt page. The URL names internal topology, so it is
        seeded out-of-band and never committed. Missing file = no page.
      '';
    };

    rdmaDevice = lib.mkOption {
      type = lib.types.str;
      default = "rdma_en2";
      description = ''
        RDMA device name for the MLX_IBV_DEVICES matrix (see `ibv_devices`).
        Port-dependent: validate on the first plug session and override per
        host if the cable lands on a different port.
      '';
    };

    wiredLimitMb = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 90000;
      description = ''
        iogpu.wired_limit_mb the watcher applies (sudo, exact-value grant
        from nix-darwin clusterLinkPrep) before starting the rank — sized for
        this node's pipeline shard, leaving the GUI working set unwirable.
        null = never touch the sysctl. When set, a failed apply SKIPS the
        rank start: serving a shard over a standalone-sized ceiling is the
        2026-07-12 dual-host panic.
      '';
    };

    standaloneWiredLimitMb = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        iogpu.wired_limit_mb the watcher restores at link-down (0 = macOS
        default ceiling). Must equal the value nix-darwin grants
        (appleSiliconTunables.wiredLimitMb, else 0).
      '';
    };

    extraServerArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra mlx_lm.server args for the cluster rank.";
    };

    prefetch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Idempotently download the cluster model at agent load (retries until complete).";
    };

    quiesceCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Worker-side hook run at link-up before the rank starts (e.g. the cluster-quiesce allowlist sweep).";
    };

    restoreCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Worker-side hook run at link-down after the rank stops.";
    };

    # --- cluster-join / cluster-detach lifecycle-command tunables ------------
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
