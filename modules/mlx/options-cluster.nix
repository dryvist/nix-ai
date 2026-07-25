#
# MLX Module — Clustered-mode option declarations
#
# Split out of ./cluster-mode.nix (which keeps the let-bindings, packages,
# config wiring, and the staticLinkIps option) purely to keep each file under
# the repo per-file size cap. The option paths are UNCHANGED
# (programs.mlx.clusterMode.*): the module system merges this declaration block
# with the staticLinkIps option + config block in cluster-mode.nix, the
# cluster-join/cluster-detach tunables in options-cluster-lifecycle.nix, and the
# agents in cluster-mode-maintenance.nix. Only `config` (for the home-directory
# default) and `lib` are referenced here.
#
{
  config,
  lib,
  ...
}:
let
  catalogData = import ./catalog-data.nix;
  clusterCatalog = lib.filterAttrs (_: entry: entry.cluster or false) catalogData;
  clusterModelKey = config.programs.mlx.clusterMode.modelCatalogKey;
in
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
      default = if clusterModelKey == null then "" else clusterCatalog.${clusterModelKey}.model;
      description = ''
        Resolved HuggingFace id of the cluster model. Prefer modelCatalogKey so
        deployed host configuration does not repeat physical model ids.
      '';
    };

    modelCatalogKey = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (lib.attrNames clusterCatalog));
      default = null;
      description = "Central catalog key for the pipeline-parallel cluster model.";
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

    maxWarmFailures = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        Consecutive post-readiness warm-generation failures before the watcher
        declares the rank wedged, halts it, and restores standalone serving.
        Readiness is a one-shot latch — once the endpoint answers a /v1/models
        probe it is never re-verified, because mlx_lm.server blocks HTTP during
        long generations and a timed probe would kill healthy ranks. A rank
        that serves the probe but hangs on real generation (INC-17070) would
        otherwise retry forever with nothing escalating.
      '';
    };

    alertUrlFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/mlx-cluster/alert-url";
      description = ''
        Untracked local file holding a Slack incoming-webhook URL for the halt
        page. A webhook URL is a write capability for its channel, so it is
        seeded out-of-band (mode 600) and never committed. Missing file = no
        page.

        Was an ntfy publish URL until 2026-07-24; ntfy is internal-only and
        nothing subscribed to it, so an armed pager rang in an empty room.
        Slack is the channel that is actually read. The alerters POST
        `{"text": ...}` as application/json — a raw body is rejected as
        invalid_payload, so the contents of this file are not interchangeable
        with an ntfy URL.
      '';
    };

    shardingMode = lib.mkOption {
      type = lib.types.enum [
        "tensor-parallel"
        "pipeline"
      ];
      default = "tensor-parallel";
      description = ''
        How the cluster model is split across ranks. Per-model, because the
        two modes have DISJOINT architecture support in mlx-lm and picking the
        wrong one kills the rank at startup.

        tensor-parallel (default, emits no flag) — mlx-lm's default path,
        gated on the predicate has_tensor_parallel, i.e. the model object
        exposes a shard attribute. Almost every architecture implements it,
        including every Qwen3 variant validated here (Qwen3-4B-Instruct,
        Qwen3-30B-A3B-Instruct and Qwen3.6-35B-A3B-OptiQ all clustered clean
        on 2026-07-23).

        pipeline (emits --pipeline) — opts OUT of tensor parallelism, gated on
        the predicate has_pipelining, i.e. the model object exposes an inner
        model that itself exposes a pipeline attribute. Only glm4_moe and
        glm4_moe_lite satisfy that. Selecting it for any other architecture
        fails at rank startup with "ValueError: The model does not support
        pipelining but a pipeline_group was provided" (mlx_lm/utils.py:536) —
        measured on both Qwen3-4B-Instruct and Qwen3-30B-A3B-Instruct.

        Set this to "pipeline" only alongside a GLM4-MoE cluster model.
      '';
    };

    fastMetalSync = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Set MLX_METAL_FAST_SYNCH=1 in the rank environment. This is a LATENCY
        VERSUS OBSERVABILITY trade-off with no free answer — the default
        preserves existing behaviour, the operator owns the decision.

        On (default): the MLX docs call fast Metal sync "pretty critical for
        low-latency communication" under JACCL, because the communication is
        done by the CPU. mlx/fence.h documents fast mode as requiring Metal
        3.2+ (macOS 15+), which both nodes satisfy.

        Off: GPU failures surface as exceptions instead of hangs. Measured
        2026-07-23 against one genuine Metal out-of-memory failure — with the
        flag set the rank hung silently for 900s+ (zero bytes emitted, ~100%
        CPU on both ranks, every health signal green); with it unset the SAME
        failure raised in 5.1s naming the cause ("[METAL] Command buffer
        execution failed: Insufficient Memory").

        A silent hang is the worst failure shape this cluster has: the watcher
        cannot tell it apart from a healthy idle rank. Weigh that against
        decode latency before leaving this on.
      '';
    };

    rdmaDevice = lib.mkOption {
      type = lib.types.str;
      default = "rdma_en2";
      description = ''
        Fallback RDMA device name for the MLX_IBV_DEVICES matrix (see
        `ibv_devices`). Normally UNUSED: the rank launcher discovers the
        carrier-active Thunderbolt port at start and writes the matrix from
        that, so moving the cable between ports is handled without a rebuild
        (and the two hosts may use different ports — each rank consumes only
        its own row of the matrix). This value is the override applied only
        when discovery finds no carrier-active Thunderbolt port with a
        matching rdma_ device, and the launcher logs loudly when it falls
        back.
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
  };
}
