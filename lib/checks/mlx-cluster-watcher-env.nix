# Clustered-mode compile regression tests — the coordinator WATCHER's contract.
#
# Split out of ./mlx-cluster.nix at the repo per-file size cap. Its sibling
# pins the RANK's env contract (distributed init, sharding, RDMA discovery);
# this one pins what the coordinator's link watcher needs to bring standalone
# serving back and readiness-probe the cluster endpoint. Same fixture
# (hmConfigCluster) as ./mlx-cluster.nix and ./mlx-cluster-peer-env.nix.
{
  pkgs,
  hmConfigCluster,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  # The link-down settle window in seconds, resolved to the probe count the
  # watcher actually counts in. Calls the shipped derivation directly (worker
  # shape, so the coordinator-only branch stays unevaluated) instead of
  # re-implementing the arithmetic here — a second implementation would agree
  # with the first right up until someone changed one of them.
  derivedStrikes =
    settle: tick:
    (import ../../modules/mlx/cluster-watcher-env.nix {
      inherit (pkgs) lib;
      cfg.port = 11434;
      isCoordinator = false;
      staticSelfIp = "192.168.208.2";
      staticPeerIp = "192.168.208.1";
      rankLabel = "dev.test.rank";
      warmupAgentLabel = "dev.test.warmup";
      launchAgentLabel = "dev.test.server";
      watchdogAgentLabel = "dev.test.watchdog";
      launchAgentsDir = "/tmp/LaunchAgents";
      stateFile = "/tmp/link-state";
      pdDebtFile = "/tmp/pd-debt";
      rankErrorLog = "/tmp/cluster-rank.error.log";
      ncfg = {
        role = "worker";
        maxKickstarts = 5;
        devicePdBudget = 11;
        alertUrlFile = "/tmp/alert-url";
        rendezvousPort = 11441;
        peerRendezvousProbeTimeoutSecs = 2;
        linkRepair = true;
        linkRepairActivateTimeoutSecs = 150;
        linkDownSettleSecs = settle;
        tickIntervalSecs = tick;
        wiredLimitMb = null;
        quiesceCommand = null;
        restoreCommand = null;
      };
    }).CLUSTER_LINK_DOWN_STRIKES;
in
{
  mlx-cluster-watcher-env =
    let
      agents = hmConfigCluster.config.launchd.agents;
      watcher = agents.mlx-cluster-watcher.config;
      watcherEnv = watcher.EnvironmentVariables;
    in
    assert
      watcher.StartInterval == 30 && watcher.RunAtLoad == true
      || throw "cluster: watcher must tick every 30s from load";
    assert
      watcherEnv.CLUSTER_STATIC_PEER_IP == "192.168.208.2"
      || throw "cluster: coordinator watcher must ping the worker's static link ip, got ${watcherEnv.CLUSTER_STATIC_PEER_IP}";
    assert
      watcherEnv.CLUSTER_NORMAL_PROXY == "http://127.0.0.1:11434"
      || throw "cluster: watcher must quiesce the normal-mode proxy on its configured port";
    assert
      watcherEnv.CLUSTER_HTTP_PORT == "11440"
      || throw "cluster: coordinator watcher must get the cluster endpoint port to readiness-probe";
    assert
      watcherEnv.CLUSTER_WIRED_LIMIT_MB == "90000"
      && watcherEnv.CLUSTER_STANDALONE_WIRED_LIMIT_MB == "118000"
      || throw "cluster: wired-ceiling values must reach the watcher env when wiredLimitMb is set";
    assert
      watcherEnv.CLUSTER_RANK_URL == "http://127.0.0.1:11440"
      && watcherEnv.CLUSTER_MODEL == "mlx-community/GLM-4.7-REAP-50-mxfp4"
      || throw "cluster: coordinator watcher must know the rank endpoint and model for the post-readiness warm-up";
    assert
      watcherEnv ? CLUSTER_SERVER_LABEL
      && builtins.match ".*/Library/LaunchAgents/.*[.]plist" watcherEnv.CLUSTER_SERVER_PLIST != null
      || throw "cluster: coordinator watcher must carry the standalone server label+plist, or the link-down re-warm silently no-ops when cluster-join booted that agent out";
    assert
      watcherEnv ? CLUSTER_WATCHDOG_LABEL
      || throw "cluster: coordinator watcher must carry the serving watchdog label";
    assert
      builtins.match ".*/Library/LaunchAgents/.*[.]plist" watcherEnv.CLUSTER_WATCHDOG_PLIST != null
      || throw "cluster: coordinator watcher must carry the watchdog plist, or restore_normal_serving cannot bootstrap it back after cluster-join boots it out";
    assert
      watcherEnv.CLUSTER_MAX_WARM_FAILURES == "3"
      || throw "cluster: coordinator watcher must carry the post-readiness warm-failure cap; without it a rank wedged after readiness retries forever";
    # The settle window is the ONLY thing standing between a failing rank and an
    # unbounded retry loop that burns reboot-only RDMA protection domains. Drop
    # it from the env and the script's `:-60` fallback silently takes over, so
    # the option stops controlling anything — the exact drift the derived-value
    # pins above exist to prevent.
    assert
      watcherEnv ? CLUSTER_RANK_SETTLE_SECS
      && builtins.match "[0-9]+" watcherEnv.CLUSTER_RANK_SETTLE_SECS != null
      || throw "cluster: watcher must carry the rank settle window; without it `state = running` clears the PD guard on a rank still inside the jaccl back-off, and the guard retries forever while reporting it is protecting the budget";
    # The watcher must be launched by Apple's interpreter, not its own Nix
    # shebang. macOS keys a Local Network grant to the code-signing identity,
    # and a Nix binary's identity is its content hash — so a Nix shebang here
    # means the grant dies on every rebuild and the cluster silently stops being
    # able to probe its peer. Apple's binary is identity-stable, so the agent
    # needs no grant at all. Regressing this looks like nothing until a cold
    # boot fails to form the cluster.
    assert
      builtins.head watcher.ProgramArguments == "/bin/bash"
      || throw "cluster: the watcher must be launched via Apple's /bin/bash, not its Nix shebang — a Nix interpreter's TCC identity is its content hash, so its Local Network grant dies on every rebuild and the probe starts returning 'No route to host'";
    # The peer-liveness supervisor's own env contract lives in
    # ./mlx-cluster-peer-env.nix — same fixture, split for the per-file size cap.
    assert
      watcherEnv.CLUSTER_WARM_RECHECK_SECS == "600"
      || throw "cluster: coordinator watcher must carry the health-gate soak recheck interval (vk1188), or liveness is verified at most once per link session";
    assert
      watcherEnv.CLUSTER_STATIC_SELF_IP == "192.168.208.1"
      && watcherEnv.CLUSTER_RENDEZVOUS_PORT == "11441"
      || throw "cluster: the watcher must know its OWN link address and the rendezvous port — the two rank-start preconditions (errno 49 EADDRNOTAVAIL on a missing address, errno 60 + a leaked RDMA protection domain on an absent rank 0)";
    assert
      watcherEnv.CLUSTER_PEER_PROBE_TIMEOUT_SECS == "2"
      && watcherEnv.CLUSTER_LINK_REPAIR == "1"
      && watcherEnv.CLUSTER_LINK_ACTIVATE_TIMEOUT_SECS == "150"
      || throw "cluster: rendezvous-probe bound, link-address repair switch and its bounded activation fallback must all reach the watcher as configuration, not script defaults";
    # The settle window is expressed in SECONDS and converted to probe strikes
    # against the watcher's own tick, so the two can never drift. 60s at the
    # default 30s tick is the historical 2 strikes — the unit changed, the
    # behaviour did not.
    assert
      watcherEnv.CLUSTER_LINK_DOWN_STRIKES == "2" && watcher.StartInterval == 30
      || throw "cluster: default 60s settle window at a 30s tick must be 2 confirming probes";
    assert
      derivedStrikes 45 10 == "5"
      || throw "cluster: the settle window must round UP to whole probes (45s at a 10s tick = 5), or a shortened tick silently shortens the window";
    assert
      derivedStrikes 5 30 == "1"
      || throw "cluster: a settle window shorter than one tick must still mean one CONFIRMING probe, never zero — a single dropped packet must not tear the rank down and reset the PD guard";
    helpers.mkMarker "check-mlx-cluster-watcher-env" "MLX clustered mode: coordinator watcher env contract — link timing, standalone-serving restore wiring (server, warmup, watchdog), readiness probe, and derived settle-window strikes verified";
}
