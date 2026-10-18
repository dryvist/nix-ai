#
# MLX Module — clustered-mode peer-state responder
#
# Companion to ./cluster-mode.nix. Kept separate because it owns a distinct
# resident agent and failure domain.
#
# cluster-join publishes whether this host is ready to rendezvous; this agent
# serves the state so the peer can coordinate its rank start.
#
# It is the responder half of the peer-armed handshake. cluster-join writes
# peer-state.json; this agent serves that line on the link address.
#
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared) cfg clusterSoftwareJson;
  ncfg = cfg.clusterMode;
  # Cluster override if set, else the module-wide convention
  # (./options-launch.nix). Resolved the same way the rank agent
  # resolve it, so all three are launched alike.
  appleInterp = if ncfg.appleInterpreter != null then ncfg.appleInterpreter else cfg.appleInterpreter;

  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
  isCoordinator = ncfg.role == "coordinator";
  staticSelfIp = if isCoordinator then ncfg.staticLinkIps.coordinator else ncfg.staticLinkIps.worker;
  peerStatePkg = pkgs.writeShellApplication {
    name = "mlx-cluster-peer-state";
    # The responder resets stale state before listening. nc is
    # /usr/bin/nc by absolute path, because /usr/bin is not on a
    # writeShellApplication PATH — the same trap that once disabled the PD guard
    # by putting sysctl out of reach.
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = lib.concatStrings (map builtins.readFile (import ./cluster-script-layers.nix).peerState);
  };
in
{
  config = lib.mkIf (cfg.enable && ncfg.enable) {
    launchd.agents.mlx-cluster-peer-state = {
      enable = true;
      config = {
        Label = "dev.mlx-cluster.peer-state";
        # Apple's interpreter, like every other agent in this module that
        # touches the network. A Nix binary's signing identity is its content
        # hash, so a macOS Local Network grant dies on the next rebuild — and
        # this agent's entire job is being reachable from the other Mac, which
        # sits on this Mac's own subnet.
        ProgramArguments = lib.optional (appleInterp != null) appleInterp ++ [
          (lib.getExe peerStatePkg)
        ];
        # Resident, not periodic: it must be listening whenever the peer polls,
        # and its own loop already handles the bind failing while the cable is
        # out. KeepAlive covers the one case the loop cannot — the process
        # itself dying.
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Background";
        EnvironmentVariables = {
          # The same paths reach cluster-join through cluster-cli-env.nix.
          CLUSTER_PEER_STATE_FILE = ncfg.peerStateFile;
          CLUSTER_STATE_FILE = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/link-state";
          CLUSTER_PEER_STATE_PORT = toString ncfg.peerStatePort;
          CLUSTER_STATIC_SELF_IP = staticSelfIp;
          CLUSTER_SOFTWARE_JSON = clusterSoftwareJson;
          CLUSTER_SW_VERS_BIN = "/usr/bin/sw_vers";
          # Reuses the fetch timeout as the listener's idle bound: the two
          # describe the same conversation from either end, so one number keeps
          # a client that gives up and a server that waits from disagreeing.
          CLUSTER_PEER_STATE_TIMEOUT_SECS = toString ncfg.peerStateTimeoutSecs;
          CLUSTER_PEER_STATE_RETRY_SECS = "5";
          CLUSTER_NC_BIN = "/usr/bin/nc";
        };
        StandardOutPath = "${logDir}/cluster-peer-state.log";
        StandardErrorPath = "${logDir}/cluster-peer-state.error.log";
      };
    };
  };
}
