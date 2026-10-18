# The one-shot join handshake, including peer state publication and boot reset.
{
  pkgs,
  hmConfigCluster,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  agents = hmConfigCluster.config.launchd.agents;
  responder = agents.mlx-cluster-peer-state.config;
  responderEnv = responder.EnvironmentVariables;
  ncfg = hmConfigCluster.config.programs.mlx.clusterMode;
  assertionMessages = map (assertion: assertion.message) hmConfigCluster.config.assertions;
  softwareContract = builtins.fromJSON responderEnv.CLUSTER_SOFTWARE_JSON;
in
{
  mlx-cluster-peer-armed = pkgs.runCommand "check-mlx-cluster-peer-armed" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
    ];
    RANK_LAUNCH = "${src}/modules/mlx/scripts/cluster-rank-launch.sh";
  } "cd ${src} && bash tests/test-join-handshake.sh && touch $out";

  mlx-cluster-peer-armed-env =
    assert
      responderEnv.CLUSTER_STATIC_SELF_IP == (
        if ncfg.role == "coordinator" then ncfg.staticLinkIps.coordinator else ncfg.staticLinkIps.worker
      )
      || throw "cluster: peer-state responder must bind this host's static link address";
    assert
      responderEnv.CLUSTER_PEER_STATE_FILE == ncfg.peerStateFile
      || throw "cluster: responder and lifecycle commands must share the configured peer-state path";
    assert
      responderEnv.CLUSTER_PEER_STATE_PORT == toString ncfg.peerStatePort && ncfg.peerStatePort != 0
      || throw "cluster: responder must listen on the nonzero port polled by the peer";
    assert
      responderEnv.CLUSTER_SOFTWARE_JSON != ""
      || throw "cluster: responder must publish the rendered software-version contract";
    assert
      builtins.attrNames softwareContract == [
        "macos"
        "mlx"
        "mlx_lm"
        "model"
        "model_revision"
        "nix_ai"
      ]
      && builtins.all (key: builtins.isString softwareContract.${key}) [
        "model"
        "model_revision"
        "nix_ai"
        "mlx"
        "mlx_lm"
        "macos"
      ]
      || throw "cluster: software-version contract must publish the six runtime-compared string keys";
    assert
      softwareContract.nix_ai != ""
      && softwareContract.mlx != ""
      && softwareContract.mlx_lm != ""
      && softwareContract.macos == ""
      && softwareContract.model == ncfg.model
      && softwareContract.model_revision == ""
      && pkgs.lib.hasInfix ".configurationRevision" (
        builtins.readFile ../../modules/mlx/scripts/cluster-peer-state-write.sh
      )
      || throw "cluster: software versions must use the runtime configuration revision, flake revision, and pinned MLX versions";
    assert
      ncfg.peerSsh == ""
      && builtins.any (
        message: pkgs.lib.hasInfix "peerSsh is set on the coordinator only" message
      ) assertionMessages
      || throw "cluster: coordinator SSH must default empty and reject worker configuration";
    assert
      responder.RunAtLoad == true && responder.KeepAlive == true
      || throw "cluster: peer-state responder must stay resident for the join poll";
    helpers.mkMarker "check-mlx-cluster-peer-armed-env" "peer-state responder binds the point-to-point address, serves the shared path and port, and publishes the software contract";
}
