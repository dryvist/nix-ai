# Cluster observation traps

Split out of [cluster-link-truths.md](cluster-link-truths.md) — that page
holds the state-machine rules the automation enforces; this page holds the
diagnostic gotchas that produced a confident wrong reading of the machine at
least once each. Read this before trusting any manual observation over what
the watcher itself reports.

- **`RUNNING` in ifconfig flags is NOT carrier.** It is set on an admin-up
  port with nothing plugged in. Carrier is the per-port `status:` line —
  `active`/`inactive`, read on `en1`/`en2`/`en3` individually. `bridge0`'s own
  status is irrelevant. The facts line renders this per port.
- **A missing link address means link prep did not run.** It says *nothing*
  about the cable — fully compatible with a seated cable and `status: active`.
  Only the cluster tooling aliases it, never DHCP or the bridge service.
  Enforced: carrier present + address absent self-repairs, bounded
  (`linkPrepMaxRepairs`).
- **A disabled Thunderbolt Bridge with zero members is the CORRECT state.**
  The tooling deliberately frees TB ports *from* `bridge0`; `member: enX`
  reappearing is the classic prep loss, undone by `repair_link_direct`. Do not
  "fix" it in System Settings.
- **macOS Local Network Privacy has a distinct signature and never removes an
  address**: same-subnet `EHOSTUNREACH` (**errno 65**) for a gated process
  while `/usr/bin/curl` succeeds in the same second. Both agents launch
  through Apple's interpreter (`programs.mlx.appleInterpreter`) for this
  reason. **Discriminator: errno 65 = gate blocked; errno 61
  (`ECONNREFUSED`) = reached the peer, gate clear.** The gate CAN be prompted
  from launchd; a grant persists on disk at
  `/Library/Preferences/com.apple.networkextension.plist` (`DenyAll = false`),
  not the (empty, here) TCC.db table. If `nehelper` can't resolve the
  identity's display metadata (no alert ever attempted), the resulting
  connect failures classify as ordinary Stage-A rank-start failures and drive
  the same kickstart-cap → `rank-start-failures` halt →
  [the auto-reboot path](rdma-protection-domains.md#the-watcher-reboots-itself)
  — so this failure mode already self-clears without a special case.
- **Never read halt state by file existence.** `[ -f rank-halted ]` reports
  the automation's own self-healing as an outage: post-reboot the marker
  legitimately exists for a tick before `halt_drop_if_pre_boot` drops it. Test
  the marker's `boot=` field against `sysctl -n kern.boottime`. Same family: a
  `quiesced-agents` marker is not evidence the agents are quiesced — observe
  the processes, never trust a marker over the machine.
- **Read a failure burst from the FIRST error, not the last.** 2026-08-02: the
  first rank failure was a Metal OOM
  (`kIOGPUCommandBufferCallbackErrorOutOfMemory`); every later attempt died
  `[jaccl] Couldn't connect (error: 60)` — a downstream symptom pointing at
  the network. The last error names the aftermath; the first names the cause.
- **`errno 60` never names the machine that is wrong.** It is `ETIMEDOUT`.
  Enforced: `cluster-join` probes the peer (`peerReadyTimeoutSecs`) before the
  long wait and refuses naming which side is unverified; the watcher's peer
  rung refuses a start against an absent peer — no rank, no domain spent.
- **A worker rank can die SIGSEGV (exit 139) when its peer vanishes.**
  `launchctl list`'s second column is the last exit status; a bare
  running/not-running check hides it.
