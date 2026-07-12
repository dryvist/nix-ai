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
    in
    assert
      rankEnv.MLX_RANK == "0" || throw "cluster: coordinator must be rank 0, got ${rankEnv.MLX_RANK}";
    assert
      !(rankEnv ? MLX_JACCL_COORDINATOR)
      || throw "cluster: the JACCL rendezvous address is runtime-computed by the launcher, never baked into the env";
    assert
      rankEnv.CLUSTER_LINK_DISCOVERY == "static" && rankEnv.CLUSTER_ROLE == "coordinator"
      || throw "cluster: launcher inputs wrong (link discovery must default to static — JACCL rendezvous is IPv4-only, verified 2026-07-11; role must reach the launcher)";
    assert
      rankEnv.CLUSTER_RENDEZVOUS_PORT == "11441"
      || throw "cluster: rendezvous port must reach the launcher env";
    assert
      builtins.match ".*mlx-cluster-rank-launcher.*" (builtins.head rankArgs) != null
      || throw "cluster: rank ProgramArguments must start with the link-discovery launcher";
    assert
      rankEnv.MLX_METAL_FAST_SYNCH == "1"
      || throw "cluster: MLX_METAL_FAST_SYNCH=1 missing from the rank env";
    assert
      builtins.elem "mlx_lm.server" rankArgs && builtins.elem "--pipeline" rankArgs
      || throw "cluster: rank ProgramArguments must serve via mlx_lm.server --pipeline";
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
      !(watcherEnv ? CLUSTER_PEER_IP) && watcherEnv.CLUSTER_LINK_DISCOVERY == "static"
      || throw "cluster: watcher must default to static link discovery (JACCL is IPv4-only) with the peer ip supplied as CLUSTER_STATIC_PEER_IP";
    assert
      watcherEnv.CLUSTER_STATIC_PEER_IP == "192.168.208.2"
      || throw "cluster: coordinator watcher must ping the worker's static link ip, got ${watcherEnv.CLUSTER_STATIC_PEER_IP}";
    assert
      watcherEnv.CLUSTER_NORMAL_PROXY == "http://127.0.0.1:11434"
      || throw "cluster: watcher must quiesce the normal-mode proxy on its configured port";
    assert
      agents ? mlx-cluster-prefetch
      && agents.mlx-cluster-prefetch.config.KeepAlive.SuccessfulExit == false
      || throw "cluster: prefetch agent must retry until the download completes";
    helpers.mkMarker "check-mlx-cluster" "MLX clustered mode: rank env contract, --pipeline serving, watcher wiring, and prefetch retry verified";
}
