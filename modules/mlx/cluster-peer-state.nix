#
# MLX Module — clustered-mode peer-state responder
#
# Companion to ./cluster-mode.nix and ./peer-liveness.nix, kept as its own
# module for the same reason those two are separate: one agent, one failure
# domain, independently reviewable.
#
# The watcher answers "is the cable in, and is my rank running?"; peer-liveness
# answers "is the mesh producing tokens?"; this agent answers the question
# neither could, because until now nothing on either host could ask it — "is the
# machine on the other end of the cable in any state to rendezvous?"
#
# It is the publishing half of the peer-armed handshake. The watcher writes one
# JSON line per tick (peer_state_write in ./scripts/cluster-peer-state.sh); this
# agent serves that line on the link address so the peer's start guard can read
# it before spending an RDMA protection domain on an attempt that was certain to
# fail. Rationale in full at the top of ./scripts/cluster-peer-state-serve.sh.
#
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared) cfg;
  ncfg = cfg.clusterMode;
  # Cluster override if set, else the module-wide convention
  # (./options-launch.nix). Resolved the same way the watcher, rank and
  # peer-liveness agents resolve it, so all four are launched alike.
  appleInterp = if ncfg.appleInterpreter != null then ncfg.appleInterpreter else cfg.appleInterpreter;

  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
  isCoordinator = ncfg.role == "coordinator";
  staticSelfIp = if isCoordinator then ncfg.staticLinkIps.coordinator else ncfg.staticLinkIps.worker;
  peerStatePkg = pkgs.writeShellApplication {
    name = "mlx-cluster-peer-state";
    # coreutils only: the loop cats a file, formats a response and sleeps. nc is
    # /usr/bin/nc by absolute path, because /usr/bin is not on a
    # writeShellApplication PATH — the same trap that once disabled the PD guard
    # by putting sysctl out of reach.
    runtimeInputs = [ pkgs.coreutils ];
    # No shared layers, deliberately. See the peerState entry in
    # ./cluster-script-layers.nix for why the responder computes nothing.
    text = lib.concatStrings (map builtins.readFile (import ./cluster-script-layers.nix).peerState);
  };
in
{
  config = lib.mkIf (cfg.enable && ncfg.enable && ncfg.peerStatePort != 0) {
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
          # The one definition lives on the option (see
          # ./options-cluster-peer-state.nix): the watcher writes this exact
          # path through ./cluster-watcher-env.nix, and a second derivation here
          # is how a writer and a reader end up on different files.
          CLUSTER_PEER_STATE_FILE = ncfg.peerStateFile;
          CLUSTER_PEER_STATE_PORT = toString ncfg.peerStatePort;
          CLUSTER_STATIC_SELF_IP = staticSelfIp;
          # Reuses the fetch timeout as the listener's idle bound: the two
          # describe the same conversation from either end, so one number keeps
          # a client that gives up and a server that waits from disagreeing.
          CLUSTER_PEER_STATE_TIMEOUT_SECS = toString ncfg.peerStateTimeoutSecs;
          # Pause after a failed bind. The link address does not exist while the
          # cable is out, so this is the steady state of an unplugged machine —
          # one tick of the watcher, so a replug is picked up within the same
          # quantum everything else in this subsystem converges on.
          CLUSTER_PEER_STATE_RETRY_SECS = toString ncfg.tickIntervalSecs;
          CLUSTER_NC_BIN = "/usr/bin/nc";
        };
        StandardOutPath = "${logDir}/cluster-peer-state.log";
        StandardErrorPath = "${logDir}/cluster-peer-state.error.log";
      };
    };
  };
}
