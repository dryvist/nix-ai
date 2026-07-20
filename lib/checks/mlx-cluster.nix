# Clustered-mode compile regression tests (programs.mlx.clusterMode -> launchd agents)
{ pkgs, hmConfigCluster }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  # Coordinator fixture: rank/watcher/prefetch agents must compile with the
  # distributed env contract and the --pipeline serving mode baked in.
  mlx-cluster =
    let
      agents = hmConfigCluster.config.launchd.agents;
      rank = agents.mlx-cluster-rank.config;
      watcher = agents.mlx-cluster-watcher.config;
      rankEnv = rank.EnvironmentVariables;
      watcherEnv = watcher.EnvironmentVariables;
      rankArgs = rank.ProgramArguments;
      pkgNames = map (p: p.name or "") hmConfigCluster.config.home.packages;
    in
    assert
      rankEnv.MLX_RANK == "0" || throw "cluster: coordinator must be rank 0, got ${rankEnv.MLX_RANK}";
    assert
      rankEnv.MLX_JACCL_COORDINATOR == "192.168.208.1:11441"
      || throw "cluster: rendezvous must be the coordinator's static link IPv4 + rendezvous port (JACCL is IPv4-only, verified 2026-07-11)";
    assert
      builtins.match ".*/.config/mlx-cluster/ibv-matrix.json" rankEnv.MLX_IBV_DEVICES != null
      || throw "cluster: MLX_IBV_DEVICES must point at the nix-generated ibv matrix file";
    assert
      builtins.match ".*[[]{2}null, \"rdma_en2\"[]].*"
        hmConfigCluster.config.home.file.".config/mlx-cluster/ibv-matrix.json".text != null
      || throw "cluster: the generated ibv matrix must carry the rdmaDevice name";
    assert
      builtins.match ".*uvx" (builtins.head rankArgs) != null
      || throw "cluster: rank ProgramArguments must exec uvx directly (the launcher script is gone; the env contract is declarative)";
    assert
      rankEnv.MLX_METAL_FAST_SYNCH == "1"
      || throw "cluster: MLX_METAL_FAST_SYNCH=1 missing from the rank env";
    assert
      builtins.elem "mlx_lm.server" rankArgs && builtins.elem "--pipeline" rankArgs
      || throw "cluster: rank ProgramArguments must serve via mlx_lm.server --pipeline";
    assert
      builtins.any (a: builtins.match "mlx==.*" a != null) rankArgs
      || throw "cluster: rank must pin mlx explicitly (mlx/mlx-lm lockstep pair), not ride mlx-lm's transitive floor";
    assert
      builtins.elem "mlx-community/GLM-4.7-4bit" rankArgs
      || throw "cluster: default cluster model (GLM-4.7-4bit) not in the rank ProgramArguments";
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
      watcherEnv.CLUSTER_RANK_URL == "http://127.0.0.1:11440"
      && watcherEnv.CLUSTER_MODEL == "mlx-community/GLM-4.7-4bit"
      || throw "cluster: coordinator watcher must know the rank endpoint and model for the post-readiness warm-up";
    assert
      agents ? mlx-cluster-prefetch
      && agents.mlx-cluster-prefetch.config.KeepAlive.SuccessfulExit == false
      || throw "cluster: prefetch agent must retry until the download completes";
    assert
      builtins.elem "cluster-join" pkgNames && builtins.elem "cluster-detach" pkgNames
      || throw "cluster: cluster-join and cluster-detach lifecycle commands must ship in home.packages";
    helpers.mkMarker "check-mlx-cluster" "MLX clustered mode: declarative rank env contract, --pipeline serving, watcher wiring, prefetch retry, and cluster-join/cluster-detach lifecycle commands verified";
}
