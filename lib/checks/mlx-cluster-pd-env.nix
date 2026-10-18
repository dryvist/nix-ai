# Kernel PD gate configuration and rank process contract.
{
  pkgs,
  hmConfigCluster,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  ncfg = hmConfigCluster.config.programs.mlx.clusterMode;
  peerState = hmConfigCluster.config.launchd.agents.mlx-cluster-peer-state.config;
  peerStateEnv = peerState.EnvironmentVariables;
  cliNames = map (p: p.name or "") hmConfigCluster.config.home.packages;
  envSource = builtins.readFile (src + "/modules/mlx/cluster-cli-env.nix");
  rankSource = builtins.readFile (src + "/modules/mlx/scripts/cluster-rank-status.sh");
  gateSource = builtins.readFile (src + "/modules/mlx/scripts/cluster-pd-gate.sh");
  assertionMessages = map (a: a.message) hmConfigCluster.config.assertions;
in
{
  mlx-cluster-pd-env =
    assert
      ncfg.devicePdBudget == 11 && ncfg.pdReserve == 5
      || throw "cluster: PD gate defaults must remain devicePdBudget=11 and pdReserve=5";
    assert
      builtins.any (message: pkgs.lib.hasInfix "0 < pdReserve < devicePdBudget" message) assertionMessages
      || throw "cluster: eval must enforce 0 < pdReserve < devicePdBudget";
    assert
      pkgs.lib.hasInfix "CLUSTER_PD_RESERVE = toString ncfg.pdReserve" envSource
      && pkgs.lib.hasInfix "CLUSTER_PD_DEVICE_BUDGET = toString ncfg.devicePdBudget" envSource
      || throw "cluster: lifecycle commands must receive the configured PD budget and reserve";
    assert
      pkgs.lib.hasInfix "CLUSTER_MODEL = ncfg.model" envSource
      && pkgs.lib.hasInfix "CLUSTER_SHARDING_MODE" envSource
      && pkgs.lib.hasInfix "HF_HOME = cfg.huggingFaceHome" envSource
      || throw "cluster: cluster-join must receive the model id, sharding mode, and HF cache root";
    assert
      pkgs.lib.hasInfix "rank_process_pids" rankSource
      || throw "cluster: rank absence must use the configured absolute pgrep path";
    assert
      pkgs.lib.hasInfix "held_num + 1" gateSource && pkgs.lib.hasInfix "-ge" gateSource
      || throw "cluster: PD start gate must refuse when held + 1 reaches budget - reserve";
    assert
      peerStateEnv.CLUSTER_SOFTWARE_JSON != ""
      || throw "cluster: peer-state agent must publish the software version contract";
    assert
      builtins.elem "cluster-join" cliNames && builtins.elem "cluster-detach" cliNames
      || throw "cluster: cluster-join and cluster-detach must be installed";
    helpers.mkMarker "check-mlx-cluster-pd-env" "PD budget 11, reserve 5, strict reserve assertion, configured count gate, and lifecycle command wiring verified";
}
