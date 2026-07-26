#
# MLX Module — Clustered-mode peer-liveness supervisor
#
# Companion to ./cluster-mode.nix, kept as its own module so the watcher and
# this agent stay independently reviewable. The watcher answers "is the cable
# in, and is a rank process running?"; this answers "is the mesh producing
# tokens, and if not, which side broke?" — the question that decides whether a
# silent hang is a dead peer or a wedged one.
#
# Why a second agent rather than more branches in the watcher: the watcher ticks
# every 30s and owns the link edge, where being fast matters. Liveness is the
# opposite — it must be slow and reluctant, because mlx_lm.server blocks HTTP
# during a generation, so anything eager kills healthy ranks. Two intervals, two
# failure domains, and a bug in one cannot take down the other.
#
# Rationale, thresholds and the four anti-false-positive brakes are documented
# at the top of ./scripts/cluster-peer-liveness.sh.
#
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared) cfg warmupAgentLabel launchAgentLabel;
  ncfg = cfg.clusterMode;
  pcfg = ncfg.peerLiveness;

  rankLabel = "dev.mlx-cluster.rank";
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
  stateFile = "${config.home.homeDirectory}/Library/Application Support/mlx-cluster/link-state";
  launchAgentsDir = "${config.home.homeDirectory}/Library/LaunchAgents";

  isCoordinator = ncfg.role == "coordinator";
  staticPeerIp = if isCoordinator then ncfg.staticLinkIps.worker else ncfg.staticLinkIps.coordinator;

  rankStdout = "${logDir}/cluster-rank.log";
  rankStderr = "${logDir}/cluster-rank.error.log";

  peerLivenessPkg = pkgs.writeShellApplication {
    name = "mlx-cluster-peer-liveness";
    # curl: bounded token probe + the Slack page. jq: the alert payload is
    # JSON-encoded, never string-interpolated (a rank traceback is full of
    # quotes and newlines).
    # coreutils: the shared helpers timestamp the halt marker and the
    # undelivered-pages record (date, mkdir) — declared, not leaned on from
    # launchd's ambient /bin.
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    # Same composition the watcher uses: function definitions first, then the
    # state machine (split three ways for the per-file size cap). Concatenation
    # rather than sourcing, so every body reads the CLUSTER_* env from the
    # caller's own scope at call time — and so this agent's teardown is
    # byte-identical to the watcher's instead of a second, drifting copy.
    text = lib.concatStrings [
      (builtins.readFile ./scripts/cluster-link-helpers.sh)
      (builtins.readFile ./scripts/cluster-peer-observe.sh)
      (builtins.readFile ./scripts/cluster-peer-liveness.sh)
    ];
  };
in
{
  options.programs.mlx.clusterMode.peerLiveness = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the peer-liveness supervisor alongside the link watcher. On by
        default: without it, any worker-side failure — a rank that died with a
        Python traceback, or one wedged in a Metal fence — leaves rank 0 blocked
        in jaccl recv indefinitely with the endpoint still answering 200 and
        nothing escalating.
      '';
    };

    intervalSecs = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = ''
        Seconds between supervisor ticks. Deliberately slower than the link
        watcher's 30s: most ticks do nothing but read the bytes appended to the
        rank log since the last one, and the expensive step (a bounded
        generation) is separately rate-limited by probeIntervalSecs.
      '';
    };

    probeIntervalSecs = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = ''
        Minimum seconds between active token probes. Only reached when the rank
        log has produced no token lines and no client request is in flight, so
        on a busy node no probe is ever sent.
      '';
    };

    probeTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = ''
        Timeout for one bounded (max_tokens=1) generation. Generous on purpose:
        mlx_lm.server serializes generation and blocks HTTP for its duration, so
        a probe can legitimately queue behind a long request. Shortening this is
        how a healthy rank gets killed — the escalation threshold is the
        consecutive-failure count, never the timeout.
      '';
    };

    strikes = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        Consecutive failed token probes before the rank is declared
        no-progress and torn down to standalone serving. Any success — a probe,
        or real traffic appearing in the log — clears the count. At the defaults
        this is roughly 15 minutes of provably zero tokens, plus at most
        busyStallSecs more if a stalled request is holding the endpoint open.
      '';
    };

    busyStallSecs = lib.mkOption {
      type = lib.types.int;
      default = 900;
      description = ''
        Cap on backing off behind an in-flight request that is producing no
        tokens. 0 disables the back-off entirely (not recommended — it is what
        stops a long generation being mistaken for a wedge).

        An ESTABLISHED client connection on the endpoint normally means a request
        is genuinely in flight, and deferring is what protects a healthy rank
        mid-generation from a timed probe. But that back-off used to be
        UNBOUNDED, and a WEDGED rank holds its client connection open forever —
        so the supervisor deferred on every tick and never ran at all. Not a slow
        detection: none.

        Measured 2026-07-25 by an induced kill drill. With the worker killed, the
        coordinator did not crash — its rendezvous socket went to CLOSE_WAIT, its
        process stayed up, its port kept accepting, and a real request returned
        http=000 after 60s with zero bytes and nothing in its log. That request
        held the connection, so every later tick deferred behind it.

        Safe to bound, because a real generation emits token lines and those
        short-circuit the whole check before the back-off is reached. Busy WITH
        zero new tokens for this long is a wedge, not a long answer.
      '';
    };

    deadTicks = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        Worker only: consecutive ticks with the rank agent down, while the link
        is up, before paging with the rank log's traceback. Waits a few ticks so
        the link watcher's own kickstart retries are not paged over.
      '';
    };

    logTailLines = lib.mkOption {
      type = lib.types.int;
      default = 40;
      description = "Rank-log lines attached to a page, so the cause travels with the alert.";
    };

    progressPattern = lib.mkOption {
      type = lib.types.str;
      default = "tokens-per-sec|Prompt:|Generation:";
      description = ''
        Extended regex marking token progress in the rank log. Matched only
        against bytes appended since the previous tick, so a match is a genuine
        progress edge. Tokens are the ONLY accepted evidence of liveness here:
        both ranks spin at ~100% CPU while deadlocked and launchctl reports
        `state = running` throughout, so neither CPU nor process state is
        consulted. Override if a future mlx-lm changes its generation log lines.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && ncfg.enable && pcfg.enable) {
    launchd.agents.mlx-cluster-peer-liveness = {
      enable = true;
      config = {
        Label = "dev.mlx-cluster.peer-liveness";
        # Apple's interpreter, not the script's Nix shebang — same reason as the
        # watcher: it is what lets this agent reach the peer at all. See
        # clusterMode.appleInterpreter.
        ProgramArguments = lib.optional (ncfg.appleInterpreter != null) ncfg.appleInterpreter ++ [
          (lib.getExe peerLivenessPkg)
        ];
        RunAtLoad = true;
        StartInterval = pcfg.intervalSecs;
        ProcessType = "Background";
        EnvironmentVariables = {
          CLUSTER_ROLE = ncfg.role;
          CLUSTER_RANK_LABEL = rankLabel;
          CLUSTER_STATE_FILE = stateFile;
          CLUSTER_STATIC_PEER_IP = staticPeerIp;
          # Peer evidence: the JACCL rendezvous is a TCP session between the two
          # ranks, so netstat can see the peer's rank process from either end
          # without SSH (see the script — presence is not proof of health, but
          # absence with the cable in is proof of death).
          CLUSTER_RENDEZVOUS_PORT = toString ncfg.rendezvousPort;
          CLUSTER_RANK_LOGS = "${rankStdout} ${rankStderr}";
          # mlx_lm.server writes generation timings to stderr.
          CLUSTER_RANK_PROGRESS_LOG = rankStderr;
          CLUSTER_ALERT_URL_FILE = ncfg.alertUrlFile;
          CLUSTER_WARMUP_LABEL = warmupAgentLabel;
          CLUSTER_NORMAL_PROXY = "http://127.0.0.1:${toString cfg.port}";
          CLUSTER_PEER_PROGRESS_PATTERN = pcfg.progressPattern;
          CLUSTER_PEER_PROBE_INTERVAL_SECS = toString pcfg.probeIntervalSecs;
          CLUSTER_PEER_PROBE_TIMEOUT_SECS = toString pcfg.probeTimeoutSecs;
          CLUSTER_PEER_STRIKES = toString pcfg.strikes;
          CLUSTER_PEER_BUSY_STALL_SECS = toString pcfg.busyStallSecs;
          CLUSTER_PEER_DEAD_TICKS = toString pcfg.deadTicks;
          CLUSTER_PEER_LOG_TAIL_LINES = toString pcfg.logTailLines;
        }
        // lib.optionalAttrs isCoordinator {
          # Only rank 0 binds the endpoint, so only the coordinator can observe
          # a token or detect an in-flight request.
          CLUSTER_HTTP_PORT = toString ncfg.httpPort;
          CLUSTER_RANK_URL = "http://127.0.0.1:${toString ncfg.httpPort}";
          CLUSTER_MODEL = ncfg.model;
          # Same pair cluster-detach and the watcher carry: restore_normal_serving
          # must be able to bootstrap llama-swap, or the teardown silently
          # no-ops and standalone serving never returns (INC-17071).
          CLUSTER_SERVER_LABEL = launchAgentLabel;
          CLUSTER_SERVER_PLIST = "${launchAgentsDir}/${launchAgentLabel}.plist";
        }
        // lib.optionalAttrs (ncfg.wiredLimitMb != null) {
          CLUSTER_WIRED_LIMIT_MB = toString ncfg.wiredLimitMb;
          CLUSTER_STANDALONE_WIRED_LIMIT_MB = toString ncfg.standaloneWiredLimitMb;
        }
        // lib.optionalAttrs (ncfg.restoreCommand != null) {
          CLUSTER_RESTORE_CMD = ncfg.restoreCommand;
        };
        StandardOutPath = "${logDir}/cluster-peer-liveness.log";
        StandardErrorPath = "${logDir}/cluster-peer-liveness.error.log";
      };
    };
  };
}
