# Clustered-mode compile regression tests (programs.mlx.clusterMode -> launchd agents)
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
      watcher = agents.mlx-cluster-watcher.config;
      rankEnv = rank.EnvironmentVariables;
      watcherEnv = watcher.EnvironmentVariables;
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
    assert
      builtins.match ".*/bin/mlx-cluster-rank-launch" (builtins.head rankArgs) != null
      || throw "cluster: rank ProgramArguments must start with the RDMA-discovery launcher, which execs the uvx server invocation after it";
    assert
      (rankEnv.MLX_METAL_FAST_SYNCH or null) == "1"
      || throw "cluster: fastMetalSync defaults to true, so MLX_METAL_FAST_SYNCH=1 must reach the rank env (latency vs. observability — see the option)";
    assert
      builtins.elem "mlx_lm.server" rankArgs && !(builtins.elem "--pipeline" rankArgs)
      || throw "cluster: shardingMode defaults to tensor-parallel and must emit NO --pipeline; only glm4_moe/glm4_moe_lite implement pipelining, every other model dies at rank startup under the flag";
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
      watcher.StartInterval == 30 && watcher.RunAtLoad == true
      || throw "cluster: watcher must tick every 30s from load";
    assert
      watcherEnv.CLUSTER_STATIC_PEER_IP == "192.168.208.2"
      || throw "cluster: coordinator watcher must ping the worker's static link ip, got ${watcherEnv.CLUSTER_STATIC_PEER_IP}";
    assert
      watcherEnv.CLUSTER_NORMAL_PROXY == "http://127.0.0.1:11434"
      || throw "cluster: watcher must quiesce the normal-mode proxy on its configured port";
    assert
      watcherEnv.CLUSTER_HTTP_PORT == "11440"
      || throw "cluster: coordinator watcher must get the cluster endpoint port to readiness-probe";
    assert
      watcherEnv.CLUSTER_WIRED_LIMIT_MB == "90000"
      && watcherEnv.CLUSTER_STANDALONE_WIRED_LIMIT_MB == "118000"
      || throw "cluster: wired-ceiling values must reach the watcher env when wiredLimitMb is set";
    assert
      builtins.match ".*CLUSTER_STANDALONE_PROCESS_PATTERN.*" joinScript != null
      && builtins.match ".*pgrep -f \"\\$\\{CLUSTER_STANDALONE_PROCESS_PATTERN.*" joinScript != null
      || throw "cluster: join must reap through the selected generic MLX process pattern";
    assert
      watcherEnv.CLUSTER_RANK_URL == "http://127.0.0.1:11440"
      && watcherEnv.CLUSTER_MODEL == "mlx-community/GLM-4.7-REAP-50-mxfp4"
      || throw "cluster: coordinator watcher must know the rank endpoint and model for the post-readiness warm-up";
    assert
      watcherEnv ? CLUSTER_SERVER_LABEL
      && builtins.match ".*/Library/LaunchAgents/.*[.]plist" watcherEnv.CLUSTER_SERVER_PLIST != null
      || throw "cluster: coordinator watcher must carry the standalone server label+plist, or the link-down re-warm silently no-ops when cluster-join booted that agent out (INC-17071)";
    assert
      watcherEnv.CLUSTER_MAX_WARM_FAILURES == "3"
      || throw "cluster: coordinator watcher must carry the post-readiness warm-failure cap; without it a rank wedged after readiness retries forever (INC-17070)";
    assert
      agents ? mlx-cluster-prefetch
      && agents.mlx-cluster-prefetch.config.KeepAlive.SuccessfulExit == false
      || throw "cluster: prefetch agent must retry until the download completes";
    assert
      builtins.elem "cluster-join" pkgNames && builtins.elem "cluster-detach" pkgNames
      || throw "cluster: cluster-join and cluster-detach lifecycle commands must ship in home.packages";
    helpers.mkMarker "check-mlx-cluster" "MLX clustered mode: rank env contract, tensor-parallel default sharding, runtime RDMA-device discovery, watcher wiring, prefetch retry, and cluster-join/cluster-detach lifecycle commands verified";
}
