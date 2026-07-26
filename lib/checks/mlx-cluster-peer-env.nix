# Peer-liveness env-wiring contract (programs.mlx.clusterMode -> peer-liveness agent)
#
# Split out of ./mlx-cluster.nix purely to keep each file under the repo per-file
# size cap; the fixture and the intent are unchanged.
#
# The seam is real, not arbitrary. Its sibling pins the WATCHER's contract — link
# timing, repair, rank-start preconditions. This file pins the SUPERVISOR's: the
# peer-liveness agent's whole job is telling a dead peer from a wedged one, and
# every input to that decision arrives as env wiring. A threshold that silently
# stops reaching the agent does not fail loudly — the script falls back to its
# own inline default and the option quietly stops controlling anything, which is
# exactly the blind spot this agent exists to remove.
{
  pkgs,
  hmConfigCluster,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  mlx-cluster-peer-env =
    let
      agents = hmConfigCluster.config.launchd.agents;
      rank = agents.mlx-cluster-rank.config;
      watcher = agents.mlx-cluster-watcher.config;
      peer = agents.mlx-cluster-peer-liveness.config;
      watcherEnv = watcher.EnvironmentVariables;
      peerEnv = peer.EnvironmentVariables;
      # Compared as a whole, so a threshold that silently stops reaching the
      # agent fails the check instead of falling back to a script default.
      peerThresholds = {
        inherit (peerEnv)
          CLUSTER_PEER_STRIKES
          CLUSTER_PEER_PROBE_INTERVAL_SECS
          CLUSTER_PEER_PROBE_TIMEOUT_SECS
          CLUSTER_PEER_DEAD_TICKS
          ;
      };
    in
    assert
      peer.RunAtLoad == true && peer.StartInterval == 60
      || throw "cluster: peer-liveness must tick from load, slower than the watcher (its expensive step is separately rate-limited)";
    # Same reasoning as the watcher: launched by Apple's interpreter so its
    # network access does not depend on a TCC grant that dies with the store
    # path. This agent's entire job is reaching the peer, so a Nix shebang here
    # disables it completely and silently.
    assert
      builtins.head peer.ProgramArguments == "/bin/bash"
      || throw "cluster: peer-liveness must be launched via Apple's /bin/bash — its whole job is reaching the peer, and a Nix interpreter's Local Network grant dies on every rebuild";
    assert
      peerEnv.CLUSTER_RENDEZVOUS_PORT == "11441"
      || throw "cluster: peer-liveness needs the rendezvous port — the JACCL session on it is the only no-SSH evidence about the PEER's rank process";
    # The one bound standing between a stalled request and a supervisor that
    # never runs. Drop it from the env and the script's `:-900` fallback takes
    # over silently, so the option stops controlling anything.
    assert
      peerEnv ? CLUSTER_PEER_BUSY_STALL_SECS
      && builtins.match "[0-9]+" peerEnv.CLUSTER_PEER_BUSY_STALL_SECS != null
      || throw "cluster: peer-liveness must carry the busy-stall cap; without it the back-off behind an in-flight request is unbounded, and a wedged rank holds that request open forever, so the supervisor defers on every tick and never escalates at all";
    assert
      peerEnv.CLUSTER_RANK_PROGRESS_LOG == rank.StandardErrorPath
      || throw "cluster: peer-liveness must count token progress from the rank's stderr, where mlx_lm.server writes generation timings";
    assert
      peerEnv.CLUSTER_RANK_URL == watcherEnv.CLUSTER_RANK_URL
      && peerEnv.CLUSTER_MODEL == watcherEnv.CLUSTER_MODEL
      || throw "cluster: coordinator peer-liveness must probe the same endpoint and model the watcher warms";
    assert
      peerEnv.CLUSTER_HTTP_PORT == watcherEnv.CLUSTER_HTTP_PORT
      || throw "cluster: peer-liveness needs the endpoint port to see an in-flight request; probing over one is how a HEALTHY busy rank gets killed";
    assert
      peerThresholds == {
        CLUSTER_PEER_STRIKES = "3";
        CLUSTER_PEER_PROBE_INTERVAL_SECS = "300";
        CLUSTER_PEER_PROBE_TIMEOUT_SECS = "120";
        CLUSTER_PEER_DEAD_TICKS = "3";
      }
      || throw "cluster: every peer-liveness threshold must arrive from the options — the script's inline defaults are a last resort, never the configured value";
    assert
      builtins.all (k: peerEnv ? ${k}) [
        "CLUSTER_ALERT_URL_FILE"
        "CLUSTER_WARMUP_LABEL"
        "CLUSTER_SERVER_PLIST"
      ]
      || throw "cluster: peer-liveness must be able to page AND restore standalone serving, or a confirmed wedge just sits there";
    assert
      watcherEnv ? CLUSTER_RANK_START_ALIGN_SECS
      && pkgs.lib.toInt watcherEnv.CLUSTER_RANK_START_ALIGN_SECS > watcher.StartInterval
      || throw "cluster: the shared rank-start boundary must be strictly greater than the watcher tick, or ticks either side of a boundary map to different boundaries and the two ranks never start together";
    helpers.mkMarker "check-mlx-cluster-peer-env" "MLX peer-liveness env contract: rendezvous port, busy-stall cap, progress log, endpoint/model agreement with the watcher, every threshold arriving from options, and the page+restore wiring verified";
}
