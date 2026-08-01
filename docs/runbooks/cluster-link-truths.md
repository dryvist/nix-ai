# The cluster link: what is true, what is automatic, what a message means

The one authoritative page for diagnosing the two-Mac Thunderbolt link. Every
statement below has already cost real downtime.

**Read it before typing a command.** Most of it says the system already fixes
what you are about to; the rest tells apart observations that look identical and
are not.

Companions describe the *procedure*; this describes the *evidence*:
[cluster-lifecycle.md](cluster-lifecycle.md),
[rdma-protection-domains.md](rdma-protection-domains.md), and `dryvist/nix-darwin`
`docs/CLUSTER*.md`.

## 0. The rule that outranks the rest

**Any enumerated cause list is non-exhaustive — including every list here.** On
2026-08-01 the watcher logged one two-item list 10,440 times over 86 hours
("cable out, OR denied macOS Local Network permission") and the truth was
neither. A reader given two candidates picks one of them.

So the watcher no longer offers candidates. It reports measured fields:

```text
cluster-link: DOWN 42 consecutive tick(s) — tb-ports[ en1=inactive en2=active ]
  self <link-ip> NOT-ALIASED prep MISSING-WITH-CARRIER(link prep never ran on
  en2; not a cable fault) peer <peer-ip> answered=no generation state=drift
  local=a1b2c3d4e5f6 deploy=0f9e8d7c6b5a
```

Read the fields; never reason from a heading.

## 1. `RUNNING` is not carrier

`ifconfig` flags carry `RUNNING` on an administratively-up interface with
nothing plugged into it. It has never been a cable-presence signal. The
authoritative field is the per-port `status:` line — `active` means the cable is
in and the link negotiated, `inactive` means nothing is on that port.

`bridge0`'s own status is **irrelevant**. It is not the link (see §3). The
watcher renders `status:` per port in the `tb-ports[...]` field.

## 2. No link address means link prep did not run — it says nothing about the cable

The cluster aliases a static address from its point-to-point `/24`
(`programs.mlx.clusterMode.staticLinkIps`) onto whichever physical Thunderbolt
port has carrier. That is done by nix-darwin's `cluster-link-prep` at
activation, and repeated by `cluster-join` and the watcher.

**If no interface holds that address, the thing that assigns it did not run.**
That is a statement about activation, not about copper, and it is fully
compatible with a seated cable and a port at `status: active` — exactly the
state that produced the 86-hour outage, where the node had drifted off the
deployed generation so the activation never ran.

| Facts field | Means |
| --- | --- |
| `prep OK` | address aliased on a carrier-active port outside `bridge0` |
| `prep MISSING-WITH-CARRIER(...)` | cable is in; the prep that assigns the address did not run |
| `prep NO-CARRIER(...)` | no Thunderbolt port reports `status: active` — this one is the cable |

**This now repairs itself.** Carrier present and address absent makes the
watcher run the same repair `cluster-join` runs — free the port from `bridge0`,
admin-up, re-alias — bounded by `clusterMode.linkPrepMaxRepairs` consecutive
failures, with the counter reset the instant prep is healthy. If you are about
to do this by hand, read the facts line first.

## 3. An empty, disabled Thunderbolt Bridge is the CORRECT state

macOS puts Thunderbolt ports into `bridge0` by default. Cluster mode
deliberately takes them out, because a port enslaved in the bridge cannot hold
the link address. So on a healthy cluster host, **Thunderbolt Bridge is disabled
with zero members** — do not "fix" that in System Settings.

A port reappearing as `member: enX` in `ifconfig bridge0` is **the classic prep
loss**: it is how the link address gets dropped, and it is what
`repair_link_direct` undoes. Re-enabling the bridge re-creates the failure.

## 4. macOS Local Network privacy (TCC) is real, with a DIFFERENT signature

It exists, it was not what happened on 2026-08-01, and confusing the two sends
you to the wrong machine. TCC gates connections to hosts on the Mac's own subnet
and the verdict attaches to the responsible GUI app, which every spawned process
inherits. Its signature:

- a non-Apple-signed process gets `EHOSTUNREACH` to a same-subnet peer **while
  `/usr/bin/curl` or `/sbin/ping` succeeds against the same host and port in the
  same second** (measured 2026-07-25: a shell pinged 75/75, the agent 0/5);
- the interface, its address, the route and the ARP entry are all **valid**
  throughout.

**TCC never removes an interface address**, so `self <ip> NOT-ALIASED` is never
TCC. Address present, carrier active, peer answering a shell but not the agent —
that is TCC, and the fix is the launch path. Both cluster agents already launch
through Apple's interpreter for this reason (`programs.mlx.appleInterpreter`); a
Nix shebang anywhere in the chain makes the store path the responsible binary
and its grant dies on every rebuild.

## 5. Coordinator readiness is a ONE-SHOT latch — a `/v1/models` 200 is not health

The readiness probe fires until `:$httpPort/v1/models` answers once, then never
again. That is deliberate: `mlx_lm.server` blocks HTTP for the duration of a
generation, so a timed probe would kill healthy ranks mid-answer.

The consequence: **a 200 can persist over a rank that can no longer generate at
all.** Measured 2026-07-25 — an 8-token completion returned 0 bytes after 900s
while both ranks spun at ~100% CPU (coordinator in `jaccl::MeshImpl::recv`,
worker in `mlx::core::Fence::wait`), readiness still latched, endpoint still
answering.

**Verify with a real completion, never with `/v1/models`.** The watcher's warm
generation, the peer-liveness token probe and `cluster-detach`'s restore check
all require a generated token. The wedge detector re-arms on
`clusterMode.warmRecheckSecs`, so it catches a rank that wedges *after* its
first warm, not only before.

## 6. The RDMA protection-domain ledger is BOOT-scoped, and goes inert if mis-assembled

Every failed `mx.distributed.init()` leaks a kernel RDMA protection domain, the
device budget is small (measured `max_pd` = 11), and **only a reboot returns
one**. The ledger records what this boot has lost so the guard halts while
domains remain, rather than after `errno 96` proves they are gone.

Two ways it silently stops working, both observed:

- **Sourced without the boot-scope helper.** `current_boot_epoch` lives in
  `modules/mlx/scripts/cluster-boot-scope.sh` and must be concatenated **first**.
  Without it every halt records `boot=unknown`, mismatches on every tick, and is
  dropped — the guard reports green while doing nothing.
- **A binary off the sanitized PATH.** `writeShellApplication` restricts PATH to
  `runtimeInputs`, so `sysctl`, `netstat`, `ifconfig`, `pgrep` and `kill` must be
  absolute or reached through their `CLUSTER_*_BIN` seams. A bare `sysctl`
  produced nothing in the deployed watcher while working in a shell — how the
  guard was disabled on 2026-07-26.

Detail: [rdma-protection-domains.md](rdma-protection-domains.md).

## 7. "Teardown verified" is not "serving restored"

`cluster-detach` used to print `teardown verified (markers clear, rank gone,
standalone ceiling restored)` and exit 0. On 2026-08-01 that was **true** on a
worker whose quiesced agents were all still booted out and whose endpoint refused
connections: the restore was coordinator-only. Both roles now run the same
`restore_normal_serving` — on a worker that is `cluster-restore`, which brings
back **exactly** the set `cluster-quiesce` recorded — and both must answer a
**real completion**. No restore hook or no probe URL is a **failure**, not a
pass.

## 8. Generation drift is checked on a clock, not when someone remembers

Parity against the deploy branch (`clusterMode.generationRepo`) used to be
checked only inside `cluster-join`, a command a human starts, so a drifted node
stayed drifted and its activation-managed link address was never applied.

The watcher now reads parity every `clusterMode.generationCheckSecs` (cached —
one `git ls-remote` per interval, not per tick), reports it as a facts field in
every link state, and pages **once per distinct drift**:

| State | Meaning |
| --- | --- |
| `state=ok` | this node is at deploy HEAD |
| `state=drift` | it is not — activation-managed state may be stale |
| `state=unstamped` | dirty/unstamped build; it can never match a deploy revision |
| `state=unverified` | deploy branch unreachable (offline is legitimate) |
| `state=disabled` | no `generationRepo` configured |

**The heal stays in `cluster-join`, deliberately.** A `darwin-rebuild switch`
fired from a launchd agent can be SIGKILLed mid-activation by the very
activation it is running — home-manager boots agents out to reload them — and a
half-applied activation is worse than drift. Tradeoff: correcting drift still
takes one `cluster-join`, but drift no longer costs the link, because §2's
self-heal restores the address either way.

## 9. `errno 60` never names the machine that is wrong

`RuntimeError: [jaccl] Couldn't connect (error: 60)` is `ETIMEDOUT`. It reports
that a connection did not complete and cannot say why or which end failed. On
2026-08-01 it appeared on the worker after a full 600s wait, and the cause was
the coordinator's missing link address.

`cluster-join` now probes the peer for `clusterMode.peerReadyTimeoutSecs` before
the long wait and, on silence, refuses with an attribution instead of an errno:
this side named as verified, the peer's as **unverified** — not "broken",
because the link address is the only channel to the peer, so its silence proves
nothing beyond itself. No rank starts, so no protection domain is spent.

## 10. Where the state lives

All under `~/Library/Application Support/mlx-cluster/`:

| File | Meaning |
| --- | --- |
| `link-state` | last observed link state (`up`/`down`) |
| `link-down-strikes` | failed probes while up (asymmetric debounce) |
| `link-down-quiet-ticks` | failed probes while down (report cadence) |
| `link-facts-last` | last DOWN facts line logged — a CHANGE reports at once |
| `link-prep-repairs` | failed self-heal attempts; cleared when prep is healthy |
| `generation-parity` | `<epoch> <fact>` parity cache |
| `generation-alerted` | last drift paged, so one drift pages once |
| `rank-halted` / `rank-halt-latched` | PD-guard halt and its sticky latch |
| `rank-kickstarts` | session-scoped failed-start counter |
| `pd-debt` | **boot-scoped** ledger of leaked protection domains |
| `quiesced-agents` | worker: exactly what `cluster-quiesce` booted out |

Deleting a marker is a **request**, not a fact: the watcher re-verifies the
cause before the first retry and re-halts if it still holds. Deleting `pd-debt`
returns no protection domain — nothing but a reboot does.

## 11. What is automatic now (do not do these by hand)

| Condition | What happens, unattended |
| --- | --- |
| Carrier present, link address absent | watcher repairs prep, bounded, and says so |
| Link down, state unchanged | reported on a cadence; a CHANGE reports immediately |
| Generation drift | detected on a timer in every link state, paged once |
| Peer absent | no rank started, no domain spent; `cluster-join` refuses fast and names the side |
| Rank wedged after readiness | warm re-check tears it down to standalone serving |
| Peer rank vanished | pair-wide standdown so both sides re-arm together |
| Any teardown | serving restored via the shared path, proven with a real completion |

Before running `ifconfig`, `launchctl bootstrap` or `darwin-rebuild` here, read
`~/Library/Logs/mlx-cluster/cluster-watcher.log`: the facts line gives the state
without inference, and in most rows above the system is already fixing it.
