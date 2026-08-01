# The cluster link: what is true, what is automatic, what a message means

The one authoritative page for diagnosing the two-Mac Thunderbolt link. Every
statement below is something that has already cost real downtime, written down
so nobody has to re-derive it under pressure.

**Read this before typing a command.** Most of what it says is that the system
already fixes the thing you are about to fix by hand — and the rest is a list of
observations that look like each other and are not.

Companions, none of which supersede this page:

- [cluster-lifecycle.md](cluster-lifecycle.md) — what `cluster-join` and
  `cluster-detach` do, step by step.
- [rdma-protection-domains.md](rdma-protection-domains.md) — why a failed rank
  start is expensive and why the guard refuses.
- `dryvist/nix-darwin` `docs/CLUSTER_MODE.md`, `docs/TB5-RDMA-CLUSTER.md`,
  `docs/CLUSTER-RESUMPTION-*.md` — the darwin-side configuration and the
  resumption drill. They describe the *procedure*; this page describes the
  *evidence*.

## 0. The rule that outranks the rest

**Any enumerated cause list is non-exhaustive — including every list on this
page.** On 2026-08-01 the link watcher logged one two-item cause list 10,440
times over 86 hours ("cable out, OR denied macOS Local Network permission") and
the truth was neither item. A reader given two candidates picks one of them.

So the watcher no longer offers candidates. It reports measured fields:

```text
cluster-link: DOWN 42 consecutive tick(s) — tb-ports[ en1=inactive en2=active ]
  self <link-ip> NOT-ALIASED prep MISSING-WITH-CARRIER(link prep never ran on
  en2; not a cable fault) peer <peer-ip> answered=no generation state=drift
  local=a1b2c3d4e5f6 deploy=0f9e8d7c6b5a
```

Every field is an observation. Read them; do not reason from a heading.

## 1. `RUNNING` is not carrier

`ifconfig` flags contain `RUNNING` on an administratively-up interface with
nothing plugged into it. It is not, and has never been, a cable-presence signal.

The authoritative field is the per-port `status:` line:

```console
$ ifconfig en2 | grep -w status
 status: active      # cable in, link negotiated
$ ifconfig en1 | grep -w status
 status: inactive    # nothing on this port
```

`bridge0`'s own status is **irrelevant**. It is not the link. See §3.

The watcher renders exactly this, per port, in the `tb-ports[...]` field.

## 2. No link address means link prep did not run — it says nothing about the cable

The cluster addresses the physical Thunderbolt port that has carrier with a
static address on its point-to-point `/24`
(`programs.mlx.clusterMode.staticLinkIps`). That aliasing is done by nix-darwin's
`cluster-link-prep` at activation, and repeated by `cluster-join` and by the
watcher.

**If no interface holds that address, the thing that assigns it did not run.**
That is a statement about activation, not about copper. It is compatible with a
perfectly seated cable and a port at `status: active` — which is precisely the
state that produced the 86-hour outage: the node had drifted off the deployed
system generation, so the activation that aliases the address had never run.

The two states are distinguished by carrier, and the watcher labels them:

| Facts field | Means |
| --- | --- |
| `prep OK` | address is aliased on a carrier-active port outside `bridge0` |
| `prep MISSING-WITH-CARRIER(...)` | cable is in; the prep that assigns the address did not run |
| `prep NO-CARRIER(...)` | no Thunderbolt port reports `status: active` — this one really is the cable |

**This now repairs itself.** When a port has carrier and the address is absent,
the watcher runs the same repair `cluster-join` runs — free the port from
`bridge0`, admin-up, re-alias — bounded by
`clusterMode.linkPrepMaxRepairs` consecutive failed attempts, with the counter
reset the instant prep is healthy. You should never need to do this by hand; if
you are about to, read the facts line first and check whether it already did.

## 3. An empty, disabled Thunderbolt Bridge is the CORRECT state

macOS puts Thunderbolt ports into `bridge0` by default. Cluster mode
deliberately takes them out: the rank binds the link address on the physical
port, and a port enslaved in the bridge cannot hold it.

So in a healthy cluster host:

- **Thunderbolt Bridge is disabled and has zero members.** This is correct. Do
  not "fix" it in System Settings.
- A port reappearing as `member: enX` in `ifconfig bridge0` is **the classic prep
  loss** — it is how the link address gets dropped, and it is what
  `repair_link_direct` undoes.

Re-enabling the bridge because it looks broken re-creates the failure.

## 4. macOS Local Network privacy (TCC) is a real problem with a DIFFERENT signature

It exists, it is not what happened on 2026-08-01, and confusing the two sends
you to the wrong machine.

TCC gates connections to hosts on the Mac's own subnet, and the verdict attaches
to the responsible GUI app, so every process it spawns inherits it. Its
signature:

- a non-Apple-signed process gets `EHOSTUNREACH` / "No route to host" to a
  same-subnet peer, **while `/usr/bin/curl` or `/sbin/ping` succeeds against the
  same host and port in the same second** (measured 2026-07-25: a shell pinged
  75/75 while the agent failed 5/5);
- the interface, its address, the route and the ARP entry are all **present and
  valid** throughout.

**TCC never removes an interface address.** So `self <ip> NOT-ALIASED` in the
facts line is never TCC. If the address is present, carrier is active, and the
peer still does not answer from the agent but does from a shell — that is TCC,
and the fix is the launch path, not the network. Both cluster agents are already
launched through Apple's interpreter for this reason
(`programs.mlx.appleInterpreter`); a Nix shebang anywhere in the chain makes the
Nix store path the responsible binary and its grant dies on every rebuild.

## 5. Coordinator readiness is a ONE-SHOT latch — `/v1/models` 200 is not health

The watcher's readiness probe fires until `:$httpPort/v1/models` answers once,
then never again. That is deliberate: `mlx_lm.server` blocks HTTP for the
duration of a generation, so a timed probe would kill healthy ranks mid-answer.

The consequence is that **a 200 from `/v1/models` can persist over a rank that
can no longer generate at all**. Measured 2026-07-25: an 8-token completion
returned 0 bytes after 900s while both ranks spun at ~100% CPU — the coordinator
in `jaccl::MeshImpl::recv`, the worker in `mlx::core::Fence::wait` — with
readiness still latched and the endpoint still answering.

**Verify with a real completion, never with `/v1/models`.** Everything that
claims serving works this way now: the watcher's warm generation, the
peer-liveness supervisor's token probe, and `cluster-detach`'s
restore verification all require a generated token.

The wedge detector re-arms on `clusterMode.warmRecheckSecs`, so it can catch a
rank that wedges *after* its first successful warm, not only before it.

## 6. The RDMA protection-domain ledger is BOOT-scoped, and goes inert if mis-assembled

Every failed `mx.distributed.init()` leaks a kernel RDMA protection domain, the
device budget is small (measured `max_pd` = 11), and **only a reboot returns
one**. The ledger records what this boot has already lost so the guard can halt
while domains remain rather than after `errno 96` proves they are gone.

Two ways it silently stops working, both observed:

- **Sourced without the boot-scope helper.** `current_boot_epoch` lives in
  `modules/mlx/scripts/cluster-boot-scope.sh` and must be concatenated **first**.
  Without it the `boot=` field records `unknown`, every stamp mismatches on every
  tick, and every halt is dropped — the guard reports green while doing nothing.
- **A binary off the sanitized PATH.** `writeShellApplication` restricts PATH to
  `runtimeInputs`, so `sysctl`, `netstat`, `ifconfig`, `pgrep` and `kill` must be
  absolute (or reached through their `CLUSTER_*_BIN` seams). A bare `sysctl`
  produced nothing in the deployed watcher while working in a shell — which is
  exactly how the guard was disabled on 2026-07-26.

Full treatment: [rdma-protection-domains.md](rdma-protection-domains.md).

## 7. "Teardown verified" is not "serving restored"

`cluster-detach` used to print `teardown verified (markers clear, rank gone,
standalone ceiling restored)` and exit 0. On 2026-08-01 that was **true** on a
worker whose seven quiesced agents were all still booted out and whose endpoint
answered connection-refused. The restore was coordinator-only; the worker had no
restore path at all.

Now:

- both roles run the same `restore_normal_serving` — on a worker that means
  `cluster-restore`, which bootstraps back **exactly** the agent set
  `cluster-quiesce` recorded, never a hardcoded list;
- both roles must then answer a **real completion** before detach exits 0;
- a node with no restore hook or no probe URL is a **failure**, not a pass — an
  unverifiable restore is the state this whole step exists to stop reporting as
  success;
- the summary line names only the three postconditions it actually covers.

## 8. Generation drift is checked on a clock, not when someone remembers

Parity against the deploy branch (`clusterMode.generationRepo`) used to be
checked only inside `cluster-join`, a command a human starts. A node that
drifted therefore stayed drifted, and its activation-managed link address was
never applied.

The link watcher now reads parity every `clusterMode.generationCheckSecs`
(cached, so it costs one `git ls-remote` per interval, not one per tick),
reports it as a field of the facts line in every link state, and pages **once per
distinct drift**. Five states, no inference required:

| State | Meaning |
| --- | --- |
| `state=ok` | this node is at deploy HEAD |
| `state=drift` | this node is not — activation-managed state may be stale |
| `state=unstamped` | dirty/unstamped build; it can never match a deploy revision |
| `state=unverified` | the deploy branch was unreachable (offline is legitimate) |
| `state=disabled` | no `generationRepo` configured |

**The heal stays in `cluster-join`, deliberately.** A `darwin-rebuild switch`
fired from a launchd agent can be SIGKILLed mid-activation by the very
activation it is running — home-manager boots agents out to reload them — and a
half-applied activation is worse than drift. Tradeoff, stated plainly:
correcting drift still takes one `cluster-join`, but drift no longer costs the
link, because §2's self-heal restores the address whether or not the generation
is current.

## 9. `errno 60` never names the machine that is wrong

`RuntimeError: [jaccl] Couldn't connect (error: 60)` is `ETIMEDOUT`. It reports
that a connection did not complete. It is structurally incapable of saying why,
or which end was at fault.

On 2026-08-01 it appeared on the worker after `cluster-join` had waited the full
600 s, and the cause was the coordinator's missing link address.

`cluster-join` now probes the peer for `clusterMode.peerReadyTimeoutSecs` before
the long wait and, if nothing answers, refuses with an attribution rather than an
errno: this side's prep is named as verified, the peer's is named as
**unverified** — not "broken", because the link address is the only channel to
the peer, so its silence proves nothing beyond itself. No rank is started, so no
protection domain is spent.

## 10. Where the state lives

All under `~/Library/Application Support/mlx-cluster/`:

| File | Meaning |
| --- | --- |
| `link-state` | last observed link state (`up`/`down`) |
| `link-down-strikes` | consecutive failed probes while up (asymmetric debounce) |
| `link-down-quiet-ticks` | consecutive failed probes while down (report cadence) |
| `link-facts-last` | last DOWN facts line logged — a CHANGE is reported at once |
| `link-prep-repairs` | consecutive failed self-heal attempts; cleared when prep is healthy |
| `generation-parity` | `<epoch> <fact>` parity cache |
| `generation-alerted` | last drift paged, so one drift pages once |
| `rank-halted` / `rank-halt-latched` | PD-guard halt and its sticky latch |
| `rank-kickstarts` | session-scoped failed-start counter |
| `pd-debt` | **boot-scoped** ledger of leaked protection domains |
| `quiesced-agents` | worker: exactly what `cluster-quiesce` booted out |

Deleting a marker is a **request**, not a fact: the watcher re-verifies the cause
before the first retry and re-halts if it still holds. Deleting `pd-debt` does
not return a protection domain — nothing but a reboot does.

## 11. What is automatic now (do not do these by hand)

| Condition | What happens, unattended |
| --- | --- |
| Carrier present, link address absent | watcher repairs prep, bounded, and says so |
| Link down, state unchanged | reported on a cadence; a CHANGE is reported immediately |
| Generation drift | detected on a timer in every link state, paged once |
| Peer absent | no rank started, no protection domain spent; `cluster-join` refuses fast and names the side |
| Rank wedged after readiness | warm re-check tears it down to standalone serving |
| Peer rank vanished | pair-wide standdown so both sides re-arm together |
| Any teardown | standalone serving restored via the shared path and proven with a real completion |

If you are about to run `ifconfig`, `launchctl bootstrap`, or `darwin-rebuild`
against a cluster host: check the watcher log first
(`~/Library/Logs/mlx-cluster/cluster-watcher.log`). The facts line tells you the
state without inference, and in most of the table above the system is already
fixing it.
