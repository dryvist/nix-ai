# The peer-armed handshake: its behaviour, its wiring, and its call sites.
#
# Three checks, because each one fails for a reason the other two cannot see.
#
#   mlx-cluster-peer-armed        runs tests/test-peer-armed-gate.sh against the
#                                 shipped scripts — does the gate DECIDE right?
#   mlx-cluster-peer-armed-env    pins the responder agent and the watcher env
#                                 that reaches the gate — does the decision get
#                                 the inputs it needs?
#   mlx-cluster-peer-armed-calls  pins that somebody still CALLS it — a gate
#                                 nothing invokes passes every behavioural
#                                 assertion while protecting nothing, the same
#                                 shape ./mlx-cluster-pd-callsites.nix exists for.
#
# Live cluster formation cannot be exercised in CI, so the wiring is asserted
# rather than observed.
{
  pkgs,
  hmConfigCluster,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  readScript = f: builtins.readFile (src + "/modules/mlx/scripts/${f}");
  inherit (pkgs.lib) hasInfix;
in
{
  mlx-cluster-peer-armed = pkgs.runCommand "check-mlx-cluster-peer-armed" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
    LEDGER = "${src}/modules/mlx/scripts/cluster-pd-ledger.sh";
    CAUSE = "${src}/modules/mlx/scripts/cluster-pd-cause.sh";
    RECORD = "${src}/modules/mlx/scripts/cluster-pd-record.sh";
    PEER_STATE = "${src}/modules/mlx/scripts/cluster-peer-state.sh";
  } "bash ${src}/tests/test-peer-armed-gate.sh && touch $out";

  mlx-cluster-peer-armed-env =
    let
      agents = hmConfigCluster.config.launchd.agents;
      responder = agents.mlx-cluster-peer-state.config;
      responderEnv = responder.EnvironmentVariables;
      watcherEnv = agents.mlx-cluster-watcher.config.EnvironmentVariables;
      ncfg = hmConfigCluster.config.programs.mlx.clusterMode;
      staticSelfIp =
        if ncfg.role == "coordinator" then ncfg.staticLinkIps.coordinator else ncfg.staticLinkIps.worker;
    in
    # THE ONE THING THAT WOULD MAKE THIS AGENT A LIABILITY RATHER THAN A GUARD.
    # The state names this host's system generation and its halt causes, and it
    # belongs on the point-to-point cable and nowhere else. A wildcard bind
    # would put it on every network this Mac is attached to.
    assert
      responderEnv.CLUSTER_STATIC_SELF_IP == staticSelfIp
      || throw "cluster: the peer-state responder must bind THIS host's static link address and nothing else — the published state names the system generation and every halt cause, and belongs on the cable";
    # ONE definition of the published path. A writer and a reader that each
    # derive a path are a writer and a reader on different files, and the
    # failure is silent: the responder serves a file nobody writes, the peer
    # reads a stale ts, and every start is suppressed for a reason that is not
    # the real one.
    assert
      responderEnv.CLUSTER_PEER_STATE_FILE == watcherEnv.CLUSTER_PEER_STATE_FILE
      || throw "cluster: the responder must serve the exact file the watcher publishes (programs.mlx.clusterMode.peerStateFile) — two derivations of one path is a writer and a reader on different files";
    assert
      responderEnv.CLUSTER_PEER_STATE_PORT == watcherEnv.CLUSTER_PEER_STATE_PORT
      || throw "cluster: the responder must listen on the port the peer's watcher reads";
    # nc is in /usr/bin, which is NOT on a writeShellApplication PATH. A bare
    # `nc` would leave the responder unable to listen at all — the same trap
    # that once disabled the PD guard by putting sysctl out of reach.
    assert
      responderEnv.CLUSTER_NC_BIN == "/usr/bin/nc"
      || throw "cluster: the responder needs nc by absolute path — /usr/bin is not on a writeShellApplication PATH";
    # Resident and restarted, not periodic: it must be listening whenever the
    # peer polls, and its own retry loop already covers the cable being out.
    assert
      responder.RunAtLoad == true && responder.KeepAlive == true
      || throw "cluster: the peer-state responder must run at load and be kept alive — a peer that cannot read it suppresses its own rank starts";
    # Same convention as the watcher, rank and peer-liveness agents: Apple's
    # interpreter, because a Nix binary's signing identity is its content hash
    # and a macOS Local Network grant dies on the next rebuild. This agent's
    # entire job is being reachable from the other Mac on this Mac's own subnet.
    assert
      builtins.head responder.ProgramArguments == "/bin/bash"
      || throw "cluster: the peer-state responder must be launched via Apple's /bin/bash — it exists to be reachable from the peer, and a Nix interpreter loses that grant on every rebuild";
    # Staleness is what stops a host whose watcher has died from serving
    # armed=true out of its last healthy tick forever. Derived from the tick, so
    # the two numbers cannot drift; more than one tick, so a single missed
    # publish is not treated as evidence.
    assert
      watcherEnv.CLUSTER_PEER_STATE_STALE_SECS
      == toString (ncfg.tickIntervalSecs * ncfg.peerStateStaleTicks)
      || throw "cluster: the peer-state staleness window must be derived from tickIntervalSecs, never configured twice";
    assert
      ncfg.peerStateStaleTicks > 1
      || throw "cluster: the peer-state staleness window must span more than one tick — a single missed publish is not evidence that a watcher has died, and refusing on it would suppress starts on noise";
    assert
      watcherEnv.CLUSTER_PD_CAUSE_BUDGET == toString ncfg.pdCauseBudget
      || throw "cluster: the cross-boot cause budget must reach the watcher — unset, the axis is silently inert and a repeating defect spends the same domains every boot";
    helpers.mkMarker "check-mlx-cluster-peer-armed-env" "MLX peer-armed handshake wiring: responder binds the link address only, serves the file the watcher publishes, runs resident under Apple's bash, and the staleness window and cause budget both reach the watcher";

  mlx-cluster-peer-armed-calls =
    let
      watcherSrc = readScript "cluster-link-watcher.sh";
      guardsSrc = readScript "cluster-link-guards.sh";
    in
    assert
      hasInfix "peer_state_write" watcherSrc
      || throw "cluster: the watcher must publish this host's state every tick. Without it the responder serves a file nobody writes, the peer reads a stale timestamp, and BOTH hosts suppress every start forever — the handshake fails closed, which is safe and also means the cluster never forms";
    assert
      hasInfix "peer_armed_ok" guardsSrc
      || throw "cluster: rank_start_preconditions_ok must gate on the peer being armed. Without it the strongest statement before spending a protection domain is again 'the peer answers ICMP', which is true of a host that is halted, booting, or on a different generation — five of eleven domains in eighteen minutes on 2026-08-08";
    assert
      hasInfix "peer_rearm_maybe" watcherSrc
      || throw "cluster: the watcher must attempt an auto re-arm on every up tick. Without it a pair-wide standdown is cleared only by a link cycle, so a plugged-in pair sits halted waiting for a human to replug a cable that was never out — the manual interlock the zero-AI-steps law bans";
    assert
      hasInfix "pd_cause_budget_ok" guardsSrc
      || throw "cluster: rank_start_preconditions_ok must consult the cross-boot cause budget. The boot-scoped ledger is cleared by the reboot it demands, so without this axis a repeating defect spends a full budget every boot with every guard reading green";
    helpers.mkMarker "check-mlx-cluster-peer-armed-calls" "MLX peer-armed handshake call sites: the watcher publishes and re-arms, and the start guards consult both the peer's state and the cross-boot cause budget";
}
