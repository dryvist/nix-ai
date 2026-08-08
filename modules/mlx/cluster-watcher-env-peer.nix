# Link-watcher environment contract — the peer-armed handshake half.
#
# Split out of ./cluster-watcher-env.nix at the repo per-file size cap, the same
# split-rather-than-exempt move that file itself was created by. Merged straight
# back into the same attrset, so the variables the watcher sees are unchanged.
#
# The seam is real. Its sibling derives everything this host measures about
# ITSELF — link timing, repair, memory, its own protection-domain ledger. These
# four are the only ones that describe a conversation with the OTHER machine.
{ ncfg }:
{
  # The cross-host intent channel. Until it existed, "the peer answers ICMP" was
  # the strongest statement either host could make before spending a
  # protection domain, and a host answers ICMP while halted, while booting, and
  # while running a different generation. The watcher publishes to the first
  # path and reads the peer's copy over the next three.
  #
  # The path is the OPTION's, not a second derivation: the responder agent in
  # ./cluster-peer-state.nix serves the same file, and a writer and a reader
  # that each derive a path are a writer and a reader on different files.
  CLUSTER_PEER_STATE_FILE = ncfg.peerStateFile;
  CLUSTER_PEER_STATE_PORT = toString ncfg.peerStatePort;
  CLUSTER_PEER_STATE_TIMEOUT_SECS = toString ncfg.peerStateTimeoutSecs;
  # Age at which a fetched peer state is refused, in seconds, derived from the
  # tick exactly as downStrikes and the memory dwell are — the operator
  # configures ticks, the script compares seconds, and neither number exists
  # twice. This is what stops a host whose watcher has died from serving
  # armed=true out of its last healthy tick forever.
  CLUSTER_PEER_STATE_STALE_SECS = toString (ncfg.tickIntervalSecs * ncfg.peerStateStaleTicks);
  # Cross-boot, cause-keyed protection-domain budget. maxKickstarts above is
  # boot-scoped and a reboot clears it, which is correct and is also how a
  # repeating defect spends the same five domains every boot with every guard
  # reading green. See cluster-pd-cause.sh; 0 disables the axis.
  CLUSTER_PD_CAUSE_BUDGET = toString ncfg.pdCauseBudget;
}
