# The cluster: every rule, in one place

The single authoritative page for the two-Mac Thunderbolt cluster. Every rule
below cost real downtime. **The automation is primary, the prose is the
fallback**: each rule states what the code enforces, then what a human needs
during a failure. A rule only a human can honour is a gap to file, not a rule
to write.

Procedure: [cluster-lifecycle.md](cluster-lifecycle.md). RDMA detail:
[rdma-protection-domains.md](rdma-protection-domains.md). The
`dryvist/nix-darwin` `docs/CLUSTER*.md` pages are pointers here.

## 0. The rule that outranks the rest

**Any enumerated cause list is non-exhaustive — including every list here.**
The 86-hour outage's watcher logged a two-item guess 10,440 times; the truth
was neither item. The next incident (2026-08-02) was nearly misdiagnosed as a
cable, then as generation drift; it was a Metal OOM. So the watcher reports
**measured fields** (per-port carrier, where the self address is, prep
usability, peer answer, generation parity, lease), never candidates. Read the
fields; never reason from a heading, and never stop at the first matching
cause.

## 1. Plugged in means clustered. No exceptions

Operator: *"TB5 plugged-in time is NEVER wasted. If they are plugged
in, they MUST be clustered."* Detached-while-plugged must be
**self-correcting, never stable**.

Enforced: the watcher re-admin-ups any Thunderbolt port `cluster-detach`
downed (carrier is unobservable on an admin-down port — what used to make the
detached state stable), repairs link prep, and starts the rank through the
normal guards. A real unplug changes nothing: no carrier, nothing to fix, the
watcher stays quiet.

The **one** sanctioned exception is the **standalone lease**
(`cluster-detach [secs [reason]]`, default `clusterMode.standaloneLeaseSecs`):
recorded, reason-stamped, **self-expiring**. At expiry the watcher rejoins
unattended; `cluster-join` ends it early; a garbage or unreadable lease reads
as **expired**. There is deliberately no indefinite form — an opt-out that
cannot expire is the same failure with extra steps.

## 2. Generation parity is a hard gate — before everything else

Operator: *"the actual, automated, non-AI steps enforce the nix
generations to march exactly on both / all devices before continuing with
other setup automated steps."* Drift is how the 86-hour outage happened: the
activation that aliases the link address had never run.

Enforced: parity (against `clusterMode.generationRepo` HEAD) is the **first
read of every watcher tick** and a precondition rung — under `drift` or
`unstamped`, no reap, link prep, quiesce, ceiling write or rank start happens,
and no attempt is consumed.

**Corrected 2026-08-16 — drift does NOT self-heal.** An earlier version of this
page said the watcher rebuilds the drifted host unattended. That was wrong, and
the wrongness was structural, not a bug: parity is judged against one repo's
`origin/main`, so a host legitimately deployed from a different flake would
report drift on every tick forever, and an automatic rebuild there would
silently replace that host's correct configuration with the wrong repo's — a
repair has to know what to repair *into*, and the watcher has no way to know.
`generation_heal_maybe` (`modules/mlx/scripts/cluster-generation-heal.sh`) only
pages, once per distinct deploy revision, and rank starts stay refused until a
human runs `darwin-rebuild switch` from the flake that actually owns that host.
**Generation drift is a permanent human-requiring stop.** `cluster-join` still
heals nothing either; a by-hand halt clear during drift is re-halted naming the
gate.

Parity is a *preventive control*, not the usual suspect: on 2026-08-02 all
nodes matched deploy HEAD exactly and the cause was a Metal OOM (§6). See §0.

## 3. The budget is 200 GB aggregate, never 100 GB per host

Operator: *"WE HAVE TWO 128GB Macs. AT A MINIMUM, THE MAXIMUM IS
200GB right now and ALWAYS, 100% of the time WHILE PLUGGED IN."* Clustered
capacity is the **sum** of the members' wired ceilings (2 × 102400 MB ≈
200 GB). Any sentence, sizing decision or guard that treats one host's
102400 MB as what the *cluster* can hold is a prose bug. Detaching to "free
memory" for a workload that fits under the aggregate is exactly the waste §1
forbids — run it clustered. Per-host ceilings stay real as single-host safety
guards (a shard must fit its own host beside the ~28 GiB OS reserve), never as
cluster capacity.

## 4. Reading the machine — the observation traps

Each produced a confident wrong diagnosis at least once.

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
  address**: same-subnet `EHOSTUNREACH` (**errno 65**, "no route to host") for
  a gated process while `/usr/bin/curl` succeeds in the same second,
  interface/route/ARP all valid. `NOT-ALIASED` is never this gate. Both agents
  launch through Apple's interpreter (`programs.mlx.appleInterpreter`) for this
  reason. **The single cheapest discriminator: errno 65 (near-instant) means
  the gate blocked the probe before it left the host; errno 61
  (`ECONNREFUSED`) means the probe reached the peer's TCP stack and the gate is
  clear** — one PD-free plain-socket probe answers "is Local Network Privacy
  the problem" without touching a rank. **This gate CAN be prompted from a
  launchd context** — `nehelper`'s own log reads "Showing local network alert
  … even though not in the foreground" — so "launchd can never be prompted" is
  false, and a grant made this way persists on disk at
  `/Library/Preferences/com.apple.networkextension.plist` (`DenyAll = false`),
  not in the classic TCC.db `kTCCServiceLocalNetwork` table, which stays empty
  for this gate and is the wrong place to look.
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

## 5. Serving truths

- **The endpoint lives on the COORDINATOR only** (rank 0 binds `:11440`).
  Probing `:11440` on the worker means nothing.
- **Acceptance is a real completion returning coherent text — never a
  `/v1/models` 200.** The readiness latch is one-shot (nix-ai#1275): a 200 can
  persist over a rank that generates nothing (observed repeatedly, latest
  2026-08-02). Enforced: the watcher's warm generation and re-check
  (`warmRecheckSecs`), the peer-liveness probe and `cluster-detach`'s restore
  check all require a generated token. Any monitor treating a 200 as health is
  wrong.
- **`cluster-join` on the coordinator boots out standalone serving.** Anything
  depending on that backend needs a working failover *before* the join.
- **"Teardown verified" is not "serving restored".** Both roles restore
  through the one shared `restore_normal_serving` (worker: `cluster-restore`,
  exactly the set `cluster-quiesce` recorded) and must prove it with a real
  completion; a missing restore hook or probe URL is a **failure**, not a
  pass. The summary names only what it verified.
- **Never `pkill -9` a serving process.** A SIGKILLed rank leaks its RDMA
  protection domain *and* its wired shard memory. Use the supervised tools;
  the one audited SIGKILL lives in `cluster-detach`, which records the debt.
- **The alert channel is not load-bearing.** Pages fail (observed `http=502`);
  every non-delivery logs the full text into `alerts-undelivered.log`. Never
  build a recovery step that waits on a page.

## 6. The boot boundary: what only a reboot returns

**Only a reboot returns RDMA protection domains and unreclaimed wired Metal
memory.** Both are boot-scoped kernel state. A PD-exhausted host **cannot
cluster again until it reboots** — clearing `rank-halted` returns nothing, and
`halt_clear_accepted` re-verifies and re-halts on the still-true cause.
Routing around the guard is never the answer; it burned the remaining domains
on 2026-07-24.

Enforced: every leak is written to the boot-scoped `pd-debt` ledger (failed
distributed inits, audited SIGKILLs); starts halt at a cap that *reserves*
domains (device budget: 11); `cluster-join` refuses at the cap. The design
completes with a memory-headroom precondition (a shard that cannot fit is a
refused start, not a leak — the 2026-08-02 Metal OOM) and automatic
self-reboot at exhaustion, so the terminal state needs no human.

The ledger goes **inert if mis-assembled**: `cluster-boot-scope.sh` must be
concatenated first, and every system binary absolute or behind its
`CLUSTER_*_BIN` seam (`writeShellApplication` sanitizes PATH; a bare `sysctl`
silently disabled the guard once).

**The `pd-debt` ledger is a billing estimate, not a kernel read — verify with
`ioclasscount` when the number matters.** Before nix-ai #1675, the ledger
counted every kickstart *attempt* as a domain spent, including attempts that
died in jaccl's Stage A (TCP bootstrap) before `ibv_alloc_pd` — the call that
actually consumes a domain — ever ran; it once read `domains=3` against a real
count of zero. #1675 made the settle billing errno-aware so a Stage-A death no
longer bills a domain, but it is still an attempt-based estimate. The only
direct kernel read is `ioclasscount AppleThunderboltRDMAProtectionDomain` (and
`AppleThunderboltRDMAQueuePair` for mesh state) — use it, not the ledger, when
deciding whether a host can still cluster.

## 7. The reboot recovery path is VERIFIED end-to-end, zero AI

Observed 2026-08-02 on the coordinator, unattended: stale halt dropped by
boot-scope comparison; link prep self-repaired; PD debt read 0 for the new
boot; `iogpu.wired_limit_mb` restored by activation — it needs **no**
re-applying by hand. Post-reboot transients (a `rank-halted` file for one
tick, "no carrier-active link address" while prep settles) are the automation
working; see §4 before declaring an outage.

**The cluster CAN form fully unattended, and did (2026-08-16).** After a
converge brought both hosts to matching generations and the Local Network
grant cleared (§4), the watcher self-started, found the link up and both
hosts at parity, and completed rendezvous with no human action — cost one
protection domain per host. Any earlier belief that cluster formation needs a
manual/interactive step, or that it has never worked unattended, is stale.

## 8. Where the state lives

All under `~/Library/Application Support/mlx-cluster/`. Deleting a marker is a
**request**, not a fact — the watcher re-verifies the cause and re-halts if it
holds. Deleting `pd-debt` returns no domain.

| File | Meaning |
| --- | --- |
| `link-state`, `link-down-strikes`, `link-down-quiet-ticks` | probe state, asymmetric debounce |
| `link-facts-last` | last DOWN facts line — a CHANGE reports at once |
| `link-prep-repairs`, `port-reups` | bounded self-heal counters |
| `standalone-lease` | the §1 lease: `<expiry-epoch> <created> <reason>` |
| `generation-parity/-alerted/-heal-attempts` | §2 cache, once-per-drift page, heal budget |
| `rank-halted` / `rank-halt-latched` | halt + sticky latch (read `boot=`, §4) |
| `rank-kickstarts` | session-scoped failed-start counter |
| `pd-debt` | **boot-scoped** leaked-domain ledger |
| `quiesced-agents` | worker: what `cluster-quiesce` booted out |

## 9. What is automatic (do not do these by hand)

| Condition | Unattended behaviour |
| --- | --- |
| Detached with cable in, no lease | ports re-upped, prep repaired, rejoined |
| Standalone lease expires | rejoin resumes that tick |
| Carrier present, address absent | link prep repaired, bounded |
| Generation drift | detected on a clock, healed detached, paged once |
| Peer absent / unprepared | start refused, no domain spent, side named |
| Rank wedged after readiness | torn down to standalone on failed warm re-checks |
| Peer rank vanished | pair-wide standdown so both re-arm together |
| Any teardown | serving restored via the shared path, proven by a completion |
| Reboot | stale verdicts dropped, prep repaired, ledger reset — §7 |

Before touching `ifconfig`, `launchctl` or `darwin-rebuild` by hand, read
`~/Library/Logs/mlx-cluster/cluster-watcher.log`: the system is usually
already fixing it.
