# Clustered-mode compile regression tests (programs.mlx.clusterMode -> launchd agents)
{
  pkgs,
  hmConfigCluster,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  # Records the posted JSON and replays a scripted status code, so the alert()
  # contract can be exercised without a network.
  fakeCurl = pkgs.writeShellScriptBin "curl" (
    builtins.readFile ../../modules/mlx/scripts/alert-payload-fakecurl.sh
  );

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
      ncfg = {
        role = "worker";
        maxKickstarts = 3;
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
  # alert() Slack contract. Both failure modes it covers are SILENT in
  # production — malformed JSON is rejected as invalid_payload, and a non-200
  # used to vanish under `|| true` — so this is the check that fails if either
  # regresses. cluster-link-helpers.sh is function-definitions-only, so the test
  # sources it without running the watcher. mlx-watchdog.sh carries an identical
  # alert(); keep the two in step.
  mlx-cluster-alert-payload = pkgs.runCommand "check-mlx-cluster-alert-payload" {
    nativeBuildInputs = [
      fakeCurl
      pkgs.jq
      pkgs.gnugrep
    ];
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
  } (builtins.readFile ../../modules/mlx/scripts/alert-payload-test.sh);

  # Rank-start guards: the preconditions that decide whether a rank may start at
  # all, and whether a start attempt may be COUNTED against the RDMA PD guard.
  # Sources the shipped helpers + guards in the module's concatenation order and
  # stubs only the thin wrappers over macOS-only binaries
  # (ifconfig/networksetup/nc/sysctl), so the decisions under test are the real
  # ones. Replays the 2026-07-24 incident: a worker that kickstarted into an
  # absent rank 0, exhausted the guard, and was then un-halted by hand.
  mlx-cluster-rank-guards = pkgs.runCommand "check-mlx-cluster-rank-guards" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
    GUARDS = "${src}/modules/mlx/scripts/cluster-link-guards.sh";
  } "bash ${src}/tests/test-rank-start-guards.sh && touch $out";

  # Builds the three CONCATENATED cluster scripts for real. Nothing else does:
  # `nix flake check` only evaluates packages, and the repo-wide shellcheck check
  # lints each fragment on its own. Only an actual build runs
  # writeShellApplication's checkPhase — bash -n plus shellcheck at DEFAULT
  # severity, which is stricter than that sweep's `--severity=warning`.
  #
  # Concatenation is exactly where the extra strictness earns its keep: a helper
  # shipped to a consumer that never calls it fails as SC2329 (hit 2026-07-25,
  # when one shared link-prep library was handed to cluster-detach, which uses a
  # single function from it). That pressure is what keeps the layers split by
  # actual use — cluster-link-locate.sh / -repair.sh / -guards.sh — instead of one
  # grab-bag with a suppression comment on top.
  mlx-cluster-scripts-build =
    let
      agents = hmConfigCluster.config.launchd.agents;
      agentExes = map (a: builtins.head agents.${a}.config.ProgramArguments) [
        "mlx-cluster-watcher"
        # Concatenates the same helpers, so a helper change must build here too.
        "mlx-cluster-peer-liveness"
      ];
      cliExes = map pkgs.lib.getExe (
        builtins.filter (
          p:
          builtins.elem (p.name or "") [
            "cluster-join"
            "cluster-detach"
          ]
        ) hmConfigCluster.config.home.packages
      );
    in
    pkgs.runCommand "check-mlx-cluster-scripts-build" { } ''
      for exe in ${pkgs.lib.concatStringsSep " " (agentExes ++ cliExes)}; do
        test -x "$exe" || {
          echo "cluster script not executable: $exe" >&2
          exit 1
        }
      done
      touch $out
    '';

  # Peer-liveness state machine, assembling and running the REAL script with
  # launchctl/curl/netstat/ping faked (see the test header for what its fakes
  # still assume about live behaviour). Shipped with #1398 but never wired as a
  # check, so nothing ran it — including when the shared alert()/halt_write
  # helpers it concatenates changed underneath it.
  mlx-cluster-peer-liveness = pkgs.runCommand "check-mlx-cluster-peer-liveness" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.jq
    ];
  } "bash ${src}/tests/test-peer-liveness.sh && touch $out";

  # Link-probe debounce: down is earned over the settle window, up is believed at
  # once. Mirror-style by necessity (see the test header).
  mlx-cluster-link-debounce = pkgs.runCommand "check-mlx-cluster-link-debounce" {
    nativeBuildInputs = [ pkgs.coreutils ];
  } "bash ${src}/tests/test-link-debounce.sh && touch $out";

  # Coordinator fixture: rank/watcher/prefetch agents must compile with the
  # distributed env contract. The fixture leaves shardingMode and fastMetalSync
  # at their defaults, so it also pins those defaults.
  mlx-cluster =
    let
      agents = hmConfigCluster.config.launchd.agents;
      rank = agents.mlx-cluster-rank.config;
      watcher = agents.mlx-cluster-watcher.config;
      peer = agents.mlx-cluster-peer-liveness.config;
      rankEnv = rank.EnvironmentVariables;
      watcherEnv = watcher.EnvironmentVariables;
      peerEnv = peer.EnvironmentVariables;
      # Compared as a whole below, so a threshold that silently stops reaching
      # the agent fails the check instead of falling back to a script default.
      peerThresholds = {
        inherit (peerEnv)
          CLUSTER_PEER_STRIKES
          CLUSTER_PEER_PROBE_INTERVAL_SECS
          CLUSTER_PEER_PROBE_TIMEOUT_SECS
          CLUSTER_PEER_DEAD_TICKS
          ;
      };
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
    assert
      builtins.match ".*/bin/mlx-cluster-rank-launch" (builtins.head rankArgs) != null
      || throw "cluster: rank ProgramArguments must start with the RDMA-discovery launcher, which execs the uvx server invocation after it";
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
    # Peer-liveness supervisor. Its whole job is telling a dead peer from a
    # wedged one, and every input to that decision is env wiring — so a silent
    # drop here would restore the exact blind spot it exists to remove.
    assert
      peer.RunAtLoad == true && peer.StartInterval == 60
      || throw "cluster: peer-liveness must tick from load, slower than the watcher (its expensive step is separately rate-limited)";
    assert
      peerEnv.CLUSTER_RENDEZVOUS_PORT == "11441"
      || throw "cluster: peer-liveness needs the rendezvous port — the JACCL session on it is the only no-SSH evidence about the PEER's rank process";
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
