# Cluster rank and package contract.
{
  pkgs,
  hmConfigCluster,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  mlx-cluster =
    let
      agents = hmConfigCluster.config.launchd.agents;
      rank = agents.mlx-cluster-rank.config;
      rankEnv = rank.EnvironmentVariables;
      rankArgs = rank.ProgramArguments;
      pkgNames = map (p: p.name or "") hmConfigCluster.config.home.packages;
    in
    assert rankEnv.MLX_RANK == "0" || throw "cluster: coordinator must be rank 0";
    assert
      rankEnv.MLX_JACCL_COORDINATOR == "192.168.208.1:11441"
      || throw "cluster: rendezvous must use the coordinator link address and configured port";
    assert
      rankEnv.CLUSTER_IBV_MATRIX_FILE == rankEnv.MLX_IBV_DEVICES
      && rankEnv.CLUSTER_RDMA_DEVICE == "rdma_en2"
      || throw "cluster: rank launcher matrix and RDMA fallback must agree";
    assert
      builtins.match ".*/mlx-cluster/ibv-matrix.json" rankEnv.MLX_IBV_DEVICES != null
      || throw "cluster: MLX_IBV_DEVICES must point at the runtime-discovered matrix";
    assert
      !(hmConfigCluster.config.home.file ? ".config/mlx-cluster/ibv-matrix.json")
      || throw "cluster: the physical-port RDMA matrix cannot be pinned at eval";
    assert
      builtins.head rankArgs == "/bin/bash"
      || throw "cluster: the rank must use Apple's stable interpreter for its local-network grant";
    assert
      builtins.match ".*/bin/mlx-cluster-rank-launch" (builtins.elemAt rankArgs 1) != null
      || throw "cluster: rank must start through the RDMA device discovery launcher";
    assert
      (rankEnv.MLX_METAL_FAST_SYNCH or null) == "1"
      || throw "cluster: fastMetalSync must reach the rank environment";
    assert
      builtins.elem "mlx_lm.server" rankArgs && builtins.elem "--pipeline" rankArgs
      || throw "cluster: the configured pipeline-only model must receive --pipeline";
    assert
      builtins.any (a: builtins.match "mlx==.*" a != null) rankArgs
      || throw "cluster: rank must pin mlx explicitly";
    assert
      builtins.elem "mlx-community/GLM-4.7-REAP-50-mxfp4" rankArgs
      || throw "cluster: configured cluster model missing from rank arguments";
    assert
      rank.RunAtLoad == false && rank.KeepAlive == false
      || throw "cluster: rank starts only through cluster-join";
    assert rank.ProcessType == "Interactive" || throw "cluster: rank must run at Interactive QoS";
    assert
      builtins.elem "cluster-join" pkgNames && builtins.elem "cluster-detach" pkgNames
      || throw "cluster: join and detach commands must ship in home.packages";
    helpers.mkMarker "check-mlx-cluster" "MLX rank environment, runtime RDMA discovery, and explicit lifecycle commands verified";
}
