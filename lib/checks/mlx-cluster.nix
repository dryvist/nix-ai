# Clustered-mode compile regression tests — the RANK's env contract.
#
# Split from a single file at the repo per-file size cap: the watcher's own
# contract lives in ./mlx-cluster-watcher-env.nix, the peer-liveness
# supervisor's in ./mlx-cluster-peer-env.nix. Same fixture (hmConfigCluster)
# throughout.
{
  pkgs,
  hmConfigCluster,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  # Coordinator fixture: rank/watcher/prefetch agents must compile with the
  # distributed env contract. The fixture leaves shardingMode and fastMetalSync
  # at their defaults, so it also pins those defaults.
  mlx-cluster =
    let
      agents = hmConfigCluster.config.launchd.agents;
      rank = agents.mlx-cluster-rank.config;
      rankEnv = rank.EnvironmentVariables;
      rankArgs = rank.ProgramArguments;
      pkgNames = map (p: p.name or "") hmConfigCluster.config.home.packages;
      joinScript = builtins.readFile (src + "/modules/mlx/scripts/cluster-join.sh");
    in
    assert
      rankEnv.MLX_RANK == "0" || throw "cluster: coordinator must be rank 0, got ${rankEnv.MLX_RANK}";
    assert
      rankEnv.MLX_JACCL_COORDINATOR == "192.168.208.1:11441"
      || throw "cluster: rendezvous must be the coordinator's static link IPv4 + rendezvous port (JACCL is IPv4-only, verified 2026-07-11)";
    assert
      rankEnv.CLUSTER_IBV_MATRIX_FILE == rankEnv.MLX_IBV_DEVICES
      && rankEnv.CLUSTER_RDMA_DEVICE == "rdma_en2"
      || throw "cluster: the launcher needs the matrix path it rewrites plus the rdmaDevice discovery fallback, both matching MLX_IBV_DEVICES";
    assert
      builtins.match ".*/mlx-cluster/ibv-matrix.json" rankEnv.MLX_IBV_DEVICES != null
      || throw "cluster: MLX_IBV_DEVICES must point at the ibv matrix file the rank launcher rewrites";
    assert
      !(hmConfigCluster.config.home.file ? ".config/mlx-cluster/ibv-matrix.json")
      || throw "cluster: the ibv matrix must NOT be pinned at eval — it names a physical Thunderbolt port, so it is discovered and written at rank start";
    # Two assertions, because either alone permits the other's failure.
    #
    # The interpreter first. The rank is the only agent that opens the jaccl
    # rendezvous across the link, so it is the only one whose Local Network
    # grant decides whether the cluster can form at all — and a Nix interpreter
    # at the head of the chain is the responsible process, with a code-signing
    # identity that is its own content hash. Every rebuild therefore revokes
    # the grant. Apple's binary is identity-stable and needs no grant.
    #
    # The cost of regressing this is not a retry: every rank start consumes a
    # boot-scoped RDMA protection domain, and a denial is indistinguishable at
    # the call site from an absent peer. The budget gets spent proving a
    # privacy grant expired.
    assert
      builtins.head rankArgs == "/bin/bash"
      || throw "cluster: the rank must be launched via Apple's /bin/bash, not its Nix shebang — a Nix interpreter's TCC identity is its content hash, so its Local Network grant dies on every rebuild and the jaccl rendezvous starts failing like an absent peer, one protection domain per attempt";
    # ...and the launcher second, so the interpreter cannot be pointed at
    # something other than the RDMA-discovery wrapper that execs the uvx server.
    assert
      builtins.match ".*/bin/mlx-cluster-rank-launch" (builtins.elemAt rankArgs 1) != null
      || throw "cluster: rank ProgramArguments must run the RDMA-discovery launcher (after the Apple interpreter), which execs the uvx server invocation after it";
    assert
      (rankEnv.MLX_METAL_FAST_SYNCH or null) == "1"
      || throw "cluster: fastMetalSync defaults to true, so MLX_METAL_FAST_SYNCH=1 must reach the rank env (latency vs. observability — see the option)";
    assert
      builtins.elem "mlx_lm.server" rankArgs && builtins.elem "--pipeline" rankArgs
      || throw "cluster: the fixture entry is glm4_moe (pipeline-only), so --pipeline must reach the rank; without it mlx-lm makes no split and every rank loads the full model. Only glm4_moe/glm4_moe_lite may carry it — the clusterMode architecture assertion enforces that";
    assert
      builtins.any (a: builtins.match "mlx==.*" a != null) rankArgs
      || throw "cluster: rank must pin mlx explicitly (mlx/mlx-lm lockstep pair), not ride mlx-lm's transitive floor";
    assert
      builtins.elem "mlx-community/GLM-4.7-REAP-50-mxfp4" rankArgs
      || throw "cluster: configured cluster model not in the rank ProgramArguments";
    assert
      rank.RunAtLoad == false && rank.KeepAlive == false
      || throw "cluster: the rank must be started only by the link watcher";
    assert
      rank.ProcessType == "Interactive"
      || throw "cluster: rank must run Interactive QoS (Background clamps Metal decode)";
    assert
      builtins.match ".*CLUSTER_STANDALONE_PROCESS_PATTERN.*" joinScript != null
      && builtins.match ".*pgrep -f \"\\$\\{CLUSTER_STANDALONE_PROCESS_PATTERN.*" joinScript != null
      || throw "cluster: join must reap through the selected generic MLX process pattern";
    # The coordinator watcher's own env contract (link timing, standalone-serving
    # restore wiring, readiness probe, derived settle-window strikes) lives in
    # ./mlx-cluster-watcher-env.nix — same fixture, split for the per-file size
    # cap. The peer-liveness supervisor's is ./mlx-cluster-peer-env.nix.
    assert
      agents ? mlx-cluster-prefetch
      && agents.mlx-cluster-prefetch.config.KeepAlive.SuccessfulExit == false
      || throw "cluster: prefetch agent must retry until the download completes";
    assert
      builtins.elem "cluster-join" pkgNames && builtins.elem "cluster-detach" pkgNames
      || throw "cluster: cluster-join and cluster-detach lifecycle commands must ship in home.packages";
    helpers.mkMarker "check-mlx-cluster" "MLX clustered mode: rank env contract, tensor-parallel default sharding, runtime RDMA-device discovery, prefetch retry, and cluster-join/cluster-detach lifecycle commands verified";
}
