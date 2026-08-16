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
  watchdogAgentLabel,
  launchAgentsDir,
  stateFile,
  pdDebtFile,
}:
let
  # The CLUSTER RANK process pattern. Single definition, derived from the same
  # entry-point string that builds the rank argv — see ./cluster-rank-pattern.nix
  # for why this is NOT modelServerProcessPattern and must never become it.
  inherit (import ./cluster-rank-pattern.nix { inherit lib; }) clusterRankProcessPattern;

  # The four derived tick-counts (link-down settle, down-report cadence,
  # heartbeat, memory-headroom dwell) live in ./cluster-watcher-env-ticks.nix,
  # split out at the per-file size cap (same move as ./cluster-watcher-env-peer.nix
  # below). Merged straight into this attrset, so the variables the watcher sees
  # are unchanged.
  inherit (import ./cluster-watcher-env-ticks.nix { inherit ncfg; })
    downStrikes
    downReportEveryTicks
    heartbeatEveryTicks
    memHeadroomDwellTicks
    ;
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
  CLUSTER_DOWN_REPORT_EVERY = toString downReportEveryTicks;
  CLUSTER_HEARTBEAT_EVERY = toString heartbeatEveryTicks;
  # --- self-heal and drift detection, the 2026-08-01 pair ---------------------
  # The watcher probes the peer; until now it never checked its OWN link prep, so
  # a host with carrier and no link address probed, failed and logged forever —
  # 86 hours, 10,440 identical lines, with the fix (the same repair the up-path
  # already ran) one function call away. This bounds how many consecutive repair
  # attempts it makes before it stops trying and only reports; the counter resets
  # the instant prep is healthy.
  CLUSTER_LINK_PREP_MAX_REPAIRS = toString ncfg.linkPrepMaxRepairs;
  # Generation parity on the timer. The only parity check in the system used to
  # live in cluster-join, which a human has to run — so the drift that disarmed
  # link prep went unnoticed indefinitely. Same repo the join preflight uses (one
  # definition); the TTL keeps this to one `git ls-remote` per interval rather
  # than one per tick.
  CLUSTER_GENERATION_REPO = ncfg.generationRepo;
  CLUSTER_GENERATION_CHECK_SECS = toString ncfg.generationCheckSecs;
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
  # --- RDMA protection-domain guard, proactive half --------------------------
  # The pattern that finds a SURVIVING rank before a new one is started. Without
  # it rank_start_preconditions_ok refuses outright: a guard that cannot see the
  # process it guards against must not pretend the coast is clear.
  CLUSTER_RANK_PROCESS_PATTERN = clusterRankProcessPattern;
  # pgrep/kill live in /usr/bin and /bin, neither of which is on a
  # writeShellApplication PATH. Absolute, and test seams, like CLUSTER_NETSTAT_BIN.
  CLUSTER_PGREP_BIN = "/usr/bin/pgrep";
  CLUSTER_KILL_BIN = "/bin/kill";
  # How long a surviving rank gets to honour SIGTERM before the reap gives up and
  # the start is refused. Derived from the tick because the reap runs INSIDE one:
  # a grace longer than the convergence quantum would have a tick still reaping
  # when the next one is due. Same rule as every other seconds-valued watcher
  # threshold here — expressed against the one number, never configured twice.
  CLUSTER_RANK_REAP_GRACE_SECS = toString ncfg.tickIntervalSecs;
  # The ledger of protection domains this boot has already leaked, and the cap at
  # which rank starts halt.
  #
  # The cap is maxKickstarts BY DERIVATION, not by coincidence of shape. That
  # option's meaning is "how many protection-domain-leaking events this host will
  # tolerate before it refuses to start a rank" — each failed rank start leaks
  # exactly one domain, which is the entire reason the kickstart counter exists.
  # A SIGKILLed rank leaks exactly one domain too. Same resource, same budget, so
  # raising one raises the other and neither can drift into permitting more leaks
  # than the operator agreed to. They differ only in reset semantics, and
  # deliberately: kickstarts are consecutive-and-reset-on-success because a
  # successful start proves the previous failures are over, while debt is
  # cumulative-per-boot because nothing short of a reboot returns a domain.
  CLUSTER_PD_DEBT_FILE = pdDebtFile;
  CLUSTER_PD_DEBT_MAX = toString ncfg.maxKickstarts;
  # Unattended-reboot rate limit for a PD-exhaustion halt (pd-debt-exhausted or
  # rank-start-failures). 0 disables auto-reboot outright. See
  # pd_auto_reboot_if_warranted in cluster-link-guards.sh and the option's own
  # doc comment for the FileVault caveat.
  CLUSTER_PD_AUTO_REBOOT_WINDOW_SECS = toString ncfg.pdAutoRebootWindowSecs;
  # The device's own budget — measured max_pd, 11 on this hardware. Carried so
  # every operator-facing message can state the debt as a FRACTION of what the
  # device has ("3 of 11 consumed until reboot") rather than a bare count. A
  # bare "3 leaked" reads as trivial; the fraction is the severity. It is also
  # the number the reserve invariant in lib/checks/mlx-cluster-pd-env.nix
  # measures the cap against.
  CLUSTER_PD_DEVICE_BUDGET = toString ncfg.devicePdBudget;
  # Fallback device name for active_rdma_device (cluster-link-guards.sh) when
  # no carrier-active Thunderbolt port has a matching rdma_<dev> — same config
  # the rank launcher falls back to (cluster-mode.nix). Already carries the
  # "rdma_" prefix (rdmaDevice's own default).
  CLUSTER_RDMA_DEVICE = ncfg.rdmaDevice;
  # --- memory-headroom guard --------------------------------------------------
  # Expected per-rank working set; 0 disables the rung with no vm_stat read at
  # all. See options-cluster-memory.nix for why this is measured against FREE
  # memory, never wired, and mem_headroom_ok / mem_headroom_halt_if_persistent
  # in cluster-link-guards.sh for the rung itself.
  CLUSTER_SHARD_MEMORY_MB = toString ncfg.shardMemoryMb;
  # Consecutive ticks the rung may refuse before the watcher escalates from a
  # free per-tick skip to a HALT that pd_auto_reboot_if_warranted can act on.
  CLUSTER_MEM_HEADROOM_DWELL_TICKS = toString memHeadroomDwellTicks;
  # vm_stat is not on a writeShellApplication PATH; test seam, like
  # CLUSTER_NETSTAT_BIN / CLUSTER_PGREP_BIN / CLUSTER_KILL_BIN above.
  CLUSTER_VMSTAT_BIN = "/usr/bin/vm_stat";
}
// (import ./cluster-watcher-env-peer.nix { inherit ncfg; })
// lib.optionalAttrs isCoordinator {
  # Readiness probe target: launchctl liveness alone cannot see a rank hung in
  # distributed init (see the watcher script). Only rank 0 binds the endpoint, so
  # the coordinator also carries the URL and model for the post-readiness
  # first-token warm-up.
  CLUSTER_HTTP_PORT = toString ncfg.httpPort;
  CLUSTER_RANK_URL = "http://127.0.0.1:${toString ncfg.httpPort}";
  CLUSTER_MODEL = ncfg.model;
  CLUSTER_MAX_WARM_FAILURES = toString ncfg.maxWarmFailures;
  # Consecutive soak ticks the watcher may defer while a request is in flight.
  # A busy pipeline is proof of life and must not be probed; a wedged one holds
  # its connections open the same way, so the deferral is bounded here.
  CLUSTER_SOAK_BUSY_SKIP_MAX = toString ncfg.soakBusySkipMax;
  CLUSTER_WARM_RECHECK_SECS = toString ncfg.warmRecheckSecs;
  # vk1188 automated health gate + soak.
  CLUSTER_HEALTH_GATE_TIMEOUT_SECS = toString ncfg.healthGateTimeoutSecs;
  CLUSTER_HEALTH_GATE_CONCURRENCY = toString ncfg.healthGateConcurrency;
  CLUSTER_HEALTH_GATE_CONCURRENT_TIMEOUT_SECS = toString ncfg.healthGateConcurrentTimeoutSecs;
  CLUSTER_RANK_SETTLE_SECS = toString ncfg.rankSettleSecs;
  # The link-down re-warm POSTs through llama-swap, so the watcher needs to be
  # able to bootstrap that agent when cluster-join has booted it out -- otherwise
  # the kickstart silently no-ops and standalone serving never returns
  # (INC-17071). Same pair cluster-detach already carries, so both paths
  # converge.
  CLUSTER_SERVER_LABEL = launchAgentLabel;
  CLUSTER_SERVER_PLIST = "${launchAgentsDir}/${launchAgentLabel}.plist";
  # Same pair, for the serving watchdog cluster-join boots out alongside the
  # server and warmup agents: restore_normal_serving needs the plist to
  # bootstrap it back on every teardown path this watcher owns (up->down edge,
  # PD-guard halt, wedge teardown).
  CLUSTER_WATCHDOG_LABEL = watchdogAgentLabel;
  CLUSTER_WATCHDOG_PLIST = "${launchAgentsDir}/${watchdogAgentLabel}.plist";
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
