# Link-watcher environment contract.
#
# Split out of cluster-mode.nix for the per-file size cap, the same reason
# ./cluster-cli-env.nix and ./cluster-cli-builder.nix were split out. This file
# owns only the attrset; cluster-mode.nix owns the agent that consumes it.
#
# Every threshold the watcher reads is derived HERE and passed as one variable,
# so there is exactly one definition of each number in the whole system.
{
  lib,
  ncfg,
  cfg,
  isCoordinator,
  staticSelfIp,
  staticPeerIp,
  rankLabel,
  warmupAgentLabel,
  launchAgentLabel,
  launchAgentsDir,
  stateFile,
}:
let
  # The link-down settle window in the unit the watcher actually counts in:
  # consecutive failed probes. Rounded UP (integer ceil) with a floor of one, so
  # a settle window shorter than one tick still means "one confirming probe"
  # rather than "no debounce at all". Derived, never configured twice — a value
  # defined in two places is a bug even when the two agree.
  downStrikes =
    let
      ticks = (ncfg.linkDownSettleSecs + ncfg.tickIntervalSecs - 1) / ncfg.tickIntervalSecs;
    in
    if ticks < 1 then 1 else ticks;
in
{
  CLUSTER_ROLE = ncfg.role;
  CLUSTER_RANK_LABEL = rankLabel;
  CLUSTER_WARMUP_LABEL = warmupAgentLabel;
  CLUSTER_NORMAL_PROXY = "http://127.0.0.1:${toString cfg.port}";
  CLUSTER_STATE_FILE = stateFile;
  CLUSTER_MAX_KICKSTARTS = toString ncfg.maxKickstarts;
  CLUSTER_ALERT_URL_FILE = ncfg.alertUrlFile;
  CLUSTER_STATIC_PEER_IP = staticPeerIp;
  # Self address + rendezvous port: the two rank-start preconditions. The worker
  # confirms rank 0 is listening before it spends a start attempt (every failed
  # distributed init leaks a reboot-only RDMA protection domain), and BOTH roles
  # confirm this host holds its own link address before starting a rank that
  # would otherwise die with errno 49 EADDRNOTAVAIL. For a worker the peer IS the
  # coordinator, so the probe needs no second address.
  CLUSTER_STATIC_SELF_IP = staticSelfIp;
  CLUSTER_RENDEZVOUS_PORT = toString ncfg.rendezvousPort;
  CLUSTER_PEER_PROBE_TIMEOUT_SECS = toString ncfg.peerRendezvousProbeTimeoutSecs;
  CLUSTER_LINK_REPAIR = if ncfg.linkRepair then "1" else "0";
  CLUSTER_LINK_ACTIVATE_TIMEOUT_SECS = toString ncfg.linkRepairActivateTimeoutSecs;
  CLUSTER_LINK_DOWN_STRIKES = toString downStrikes;
  # Shared wall-clock start boundary for BOTH ranks. Derived from the tick so the
  # two cannot drift, and a multiple (never equal) so ticks either side of a
  # boundary still map to the same one. See cluster-link-guards.sh.
  CLUSTER_RANK_START_ALIGN_SECS = toString (ncfg.tickIntervalSecs * ncfg.rankStartAlignMultiple);
  # Pair-wide standdown: how many consecutive ticks the peer's rendezvous session
  # must be absent before this rank stands down so both re-arm together.
  CLUSTER_PEER_SESSION_STRIKES = toString ncfg.peerSessionStrikes;
  # netstat path is a test seam; production absolute path, because /usr/sbin is
  # not on a writeShellApplication PATH.
  CLUSTER_NETSTAT_BIN = "/usr/sbin/netstat";
}
// lib.optionalAttrs isCoordinator {
  # Readiness probe target: launchctl liveness alone cannot see a rank hung in
  # distributed init (see the watcher script). Only rank 0 binds the endpoint, so
  # the coordinator also carries the URL and model for the post-readiness
  # first-token warm-up.
  CLUSTER_HTTP_PORT = toString ncfg.httpPort;
  CLUSTER_RANK_URL = "http://127.0.0.1:${toString ncfg.httpPort}";
  CLUSTER_MODEL = ncfg.model;
  CLUSTER_MAX_WARM_FAILURES = toString ncfg.maxWarmFailures;
  CLUSTER_WARM_RECHECK_SECS = toString ncfg.warmRecheckSecs;
  CLUSTER_RANK_SETTLE_SECS = toString ncfg.rankSettleSecs;
  # The link-down re-warm POSTs through llama-swap, so the watcher needs to be
  # able to bootstrap that agent when cluster-join has booted it out -- otherwise
  # the kickstart silently no-ops and standalone serving never returns
  # (INC-17071). Same pair cluster-detach already carries, so both paths
  # converge.
  CLUSTER_SERVER_LABEL = launchAgentLabel;
  CLUSTER_SERVER_PLIST = "${launchAgentsDir}/${launchAgentLabel}.plist";
}
// lib.optionalAttrs (ncfg.wiredLimitMb != null) {
  CLUSTER_WIRED_LIMIT_MB = toString ncfg.wiredLimitMb;
  CLUSTER_STANDALONE_WIRED_LIMIT_MB = toString ncfg.standaloneWiredLimitMb;
}
// lib.optionalAttrs (ncfg.quiesceCommand != null) {
  CLUSTER_QUIESCE_CMD = ncfg.quiesceCommand;
}
// lib.optionalAttrs (ncfg.restoreCommand != null) {
  CLUSTER_RESTORE_CMD = ncfg.restoreCommand;
}
