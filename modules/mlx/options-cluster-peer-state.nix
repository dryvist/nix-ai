# Options for the peer-state handshake used by cluster-join.
{ config, lib, ... }:
{
  options.programs.mlx.clusterMode = {
    peerStateFile = lib.mkOption {
      type = lib.types.str;
      internal = true;
      readOnly = true;
      default = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/peer-state.json";
      description = "Shared path written by cluster-join and served to the peer.";
    };

    peerStatePort = lib.mkOption {
      type = lib.types.port;
      default = 11442;
      description = "Port serving this host's cluster state on its static Thunderbolt link address.";
    };

    peerStateTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Timeout for a single peer-state fetch.";
    };

    peerStateStaleTicks = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Legacy watcher setting retained for consumer configuration compatibility.";
    };

    pdCauseBudget = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Legacy watcher setting retained for consumer configuration compatibility.";
    };
  };
}
