# Clustered-mode compile regression tests (programs.mlx.clusterMode -> launchd agents)
{
  pkgs,
  hmConfigCluster,
  src,
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
      launchAgentsDir = "/tmp/LaunchAgents";
      stateFile = "/tmp/link-state";
      pdDebtFile = "/tmp/pd-debt";
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
  # Coordinator fixture: rank/watcher/prefetch agents must compile with the
  # distributed env contract. The fixture leaves shardingMode and fastMetalSync
  # at their defaults, so it also pins those defaults.
  mlx-cluster =
    let
      agents = hmConfigCluster.config.launchd.agents;
      rank = agents.mlx-cluster-rank.config;
      watcher = agents.mlx-cluster-watcher.config;
      rankEnv = rank.EnvironmentVariables;
      watcherEnv = watcher.EnvironmentVariables;
      rankArgs = rank.ProgramArguments;
      pkgNames = map (p: p.name or "") hmConfigCluster.config.home.packages;
      joinScript = builtins.readFile (src + "/modules/mlx/scripts/cluster-join.sh");
    in
    assert
      rankEnv.MLX_RANK == "0" || throw "cluster: coordinator must be rank 0, got ${rankEnv.MLX_RANK}";
    assert
      rankEnv.MLX_JACCL_COORDINATOR == "192.168.208.1:11441"
      || throw "cluster: rendezvous must be the coordinator's static link IPv4 + rendezvous port (JACCL is IPv4-only, verified 2026-07-11)";
    assert
      rankEnv.CLUSTER_IBV_MATRIX_FILE == rankEnv.MLX_IBV_DEVICES
      && rankEnv.CLUSTER_RDMA_DEVICE == "rdma_en2"
      || throw "cluster: the launcher needs the matrix path it rewrites plus the rdmaDevice discovery fallback, both matching MLX_IBV_DEVICES";
    assert
      builtins.match ".*/mlx-cluster/ibv-matrix.json" rankEnv.MLX_IBV_DEVICES != null
      || throw "cluster: MLX_IBV_DEVICES must point at the ibv matrix file the rank launcher rewrites";
    assert
      !(hmConfigCluster.config.home.file ? ".config/mlx-cluster/ibv-matrix.json")
      || throw "cluster: the ibv matrix must NOT be pinned at eval — it names a physical Thunderbolt port, so it is discovered and written at rank start";
    # Two assertions, because either alone permits the other's failure.
    #
    # The interpreter first. The rank is the only agent that opens the jaccl
    # rendezvous across the link, so it is the only one whose Local Network
    # grant decides whether the cluster can form at all — and a Nix interpreter
    # at the head of the chain is the responsible process, with a code-signing
    # identity that is its own content hash. Every rebuild therefore revokes
    # the grant. Apple's binary is identity-stable and needs no grant.
    #
    # The cost of regressing this is not a retry: every rank start consumes a
    # boot-scoped RDMA protection domain, and a denial is indistinguishable at
    # the call site from an absent peer. The budget gets spent proving a
    # privacy grant expired.
    assert
      builtins.head rankArgs == "/bin/bash"
      || throw "cluster: the rank must be launched via Apple's /bin/bash, not its Nix shebang — a Nix interpreter's TCC identity is its content hash, so its Local Network grant dies on every rebuild and the jaccl rendezvous starts failing like an absent peer, one protection domain per attempt";
    # ...and the launcher second, so the interpreter cannot be pointed at
    # something other than the RDMA-discovery wrapper that execs the uvx server.
    assert
      builtins.match ".*/bin/mlx-cluster-rank-launch" (builtins.elemAt rankArgs 1) != null
      || throw "cluster: rank ProgramArguments must run the RDMA-discovery launcher (after the Apple interpreter), which execs the uvx server invocation after it";
    assert
      (rankEnv.MLX_METAL_FAST_SYNCH or null) == "1"
      || throw "cluster: fastMetalSync defaults to true, so MLX_METAL_FAST_SYNCH=1 must reach the rank env (latency vs. observability — see the option)";
    assert
      builtins.elem "mlx_lm.server" rankArgs && !(builtins.elem "--pipeline" rankArgs)
      || throw "cluster: shardingMode defaults to tensor-parallel and must emit NO --pipeline; only glm4_moe/glm4_moe_lite implement pipelining, every other model dies at rank startup under the flag";
    assert
      builtins.any (a: builtins.match "mlx==.*" a != null) rankArgs
      || throw "cluster: rank must pin mlx explicitly (mlx/mlx-lm lockstep pair), not ride mlx-lm's transitive floor";
    assert
      builtins.elem "mlx-community/GLM-4.7-REAP-50-mxfp4" rankArgs
      || throw "cluster: configured cluster model not in the rank ProgramArguments";
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
      builtins.match ".*CLUSTER_STANDALONE_PROCESS_PATTERN.*" joinScript != null
      && builtins.match ".*pgrep -f \"\\$\\{CLUSTER_STANDALONE_PROCESS_PATTERN.*" joinScript != null
      || throw "cluster: join must reap through the selected generic MLX process pattern";
    assert
      watcherEnv.CLUSTER_RANK_URL == "http://127.0.0.1:11440"
      && watcherEnv.CLUSTER_MODEL == "mlx-community/GLM-4.7-REAP-50-mxfp4"
      || throw "cluster: coordinator watcher must know the rank endpoint and model for the post-readiness warm-up";
    assert
      watcherEnv ? CLUSTER_SERVER_LABEL
      && builtins.match ".*/Library/LaunchAgents/.*[.]plist" watcherEnv.CLUSTER_SERVER_PLIST != null
      || throw "cluster: coordinator watcher must carry the standalone server label+plist, or the link-down re-warm silently no-ops when cluster-join booted that agent out (INC-17071)";
    assert
      watcherEnv.CLUSTER_MAX_WARM_FAILURES == "3"
      || throw "cluster: coordinator watcher must carry the post-readiness warm-failure cap; without it a rank wedged after readiness retries forever (INC-17070)";
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
      watcherEnv.CLUSTER_WARM_RECHECK_SECS == "1800"
      || throw "cluster: coordinator watcher must carry the warm-marker re-arm interval, or the wedge detector runs at most once per link session";
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
    assert
      agents ? mlx-cluster-prefetch
      && agents.mlx-cluster-prefetch.config.KeepAlive.SuccessfulExit == false
      || throw "cluster: prefetch agent must retry until the download completes";
    assert
      builtins.elem "cluster-join" pkgNames && builtins.elem "cluster-detach" pkgNames
      || throw "cluster: cluster-join and cluster-detach lifecycle commands must ship in home.packages";
    helpers.mkMarker "check-mlx-cluster" "MLX clustered mode: rank env contract, tensor-parallel default sharding, runtime RDMA-device discovery, watcher wiring, prefetch retry, and cluster-join/cluster-detach lifecycle commands verified";
}
