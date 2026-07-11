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
      rankEnv.MLX_JACCL_COORDINATOR == "192.168.208.1:11441"
      || throw "night: JACCL rendezvous must point at the coordinator link ip:port, got ${rankEnv.MLX_JACCL_COORDINATOR}";
    assert
      rankEnv.MLX_METAL_FAST_SYNCH == "1"
      || throw "night: MLX_METAL_FAST_SYNCH=1 missing from the rank env";
    assert
      rankEnv.NIGHT_OWN_IP == "192.168.208.1"
      || throw "night: coordinator rank must carry its own link ip for device detection, got ${rankEnv.NIGHT_OWN_IP}";
    assert
      builtins.elem "mlx_lm.server" rankArgs && builtins.elem "--pipeline" rankArgs
      || throw "night: rank ProgramArguments must serve via mlx_lm.server --pipeline";
    assert
      builtins.elem "mlx-community/GLM-4.7-4bit" rankArgs
      || throw "night: default night model (GLM-4.7-4bit) not in the rank ProgramArguments";
    assert
      pkgs.lib.hasInfix "mlx-night-rank-launch" (builtins.head rankArgs)
      || throw "night: rank ProgramArguments must run through the device-detecting launcher";
    assert
      !(rankEnv ? MLX_IBV_DEVICES)
      || throw "night: MLX_IBV_DEVICES must be launcher-generated at runtime, not baked into the plist";
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
      watcherEnv.NIGHT_PEER_IP == "192.168.208.2"
      || throw "night: coordinator watcher must ping the worker link ip, got ${watcherEnv.NIGHT_PEER_IP}";
    assert
      watcherEnv.NIGHT_DAY_PROXY == "http://127.0.0.1:11434"
      || throw "night: watcher must quiesce the day proxy on its configured port";
    assert
      agents ? mlx-night-prefetch && agents.mlx-night-prefetch.config.KeepAlive.SuccessfulExit == false
      || throw "night: prefetch agent must retry until the download completes";
    helpers.mkMarker "check-mlx-night" "MLX night cluster: rank env contract, --pipeline serving, watcher wiring, and prefetch retry verified";
}
