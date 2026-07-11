# Night-cluster compile regression tests (programs.mlx.nightCluster -> launchd agents)
{ pkgs, hmConfigNight }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  # Coordinator fixture: rank/watcher/prefetch agents must compile with the
  # distributed env contract and the --pipeline serving mode baked in.
  mlx-night =
    let
      agents = hmConfigNight.config.launchd.agents;
      rank = agents.mlx-night-rank.config;
      watcher = agents.mlx-night-watcher.config;
      rankEnv = rank.EnvironmentVariables;
      watcherEnv = watcher.EnvironmentVariables;
      rankArgs = rank.ProgramArguments;
    in
    assert
      rankEnv.MLX_RANK == "0" || throw "night: coordinator must be rank 0, got ${rankEnv.MLX_RANK}";
    assert
      !(rankEnv ? MLX_JACCL_COORDINATOR)
      || throw "night: the JACCL rendezvous address is runtime-computed by the launcher, never baked into the env";
    assert
      rankEnv.NIGHT_LINK_DISCOVERY == "link-local" && rankEnv.NIGHT_ROLE == "coordinator"
      || throw "night: launcher inputs wrong (link discovery must default to link-local; role must reach the launcher)";
    assert
      rankEnv.NIGHT_RENDEZVOUS_PORT == "11441"
      || throw "night: rendezvous port must reach the launcher env";
    assert
      builtins.match ".*mlx-night-rank-launcher.*" (builtins.head rankArgs) != null
      || throw "night: rank ProgramArguments must start with the link-discovery launcher";
    assert
      rankEnv.MLX_METAL_FAST_SYNCH == "1"
      || throw "night: MLX_METAL_FAST_SYNCH=1 missing from the rank env";
    assert
      builtins.elem "mlx_lm.server" rankArgs && builtins.elem "--pipeline" rankArgs
      || throw "night: rank ProgramArguments must serve via mlx_lm.server --pipeline";
    assert
      builtins.elem "mlx-community/GLM-4.7-4bit" rankArgs
      || throw "night: default night model (GLM-4.7-4bit) not in the rank ProgramArguments";
    assert
      rank.RunAtLoad == false && rank.KeepAlive == false
      || throw "night: the rank must be started only by the link watcher";
    assert
      rank.ProcessType == "Interactive"
      || throw "night: rank must run Interactive QoS (Background clamps Metal decode)";
    assert
      watcher.StartInterval == 30 && watcher.RunAtLoad == true
      || throw "night: watcher must tick every 30s from load";
    assert
      !(watcherEnv ? NIGHT_PEER_IP) && watcherEnv.NIGHT_LINK_DISCOVERY == "link-local"
      || throw "night: watcher must use link-local peer discovery (no baked peer ip) by default";
    assert
      watcherEnv.NIGHT_DAY_PROXY == "http://127.0.0.1:11434"
      || throw "night: watcher must quiesce the day proxy on its configured port";
    assert
      agents ? mlx-night-prefetch && agents.mlx-night-prefetch.config.KeepAlive.SuccessfulExit == false
      || throw "night: prefetch agent must retry until the download completes";
    helpers.mkMarker "check-mlx-night" "MLX night cluster: rank env contract, --pipeline serving, watcher wiring, and prefetch retry verified";
}
