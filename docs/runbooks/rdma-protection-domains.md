# RDMA protection domains: the ledger, the cap, and the reboot

A JACCL rank allocates a kernel **RDMA protection domain**. Nothing but a reboot
returns one. A host that loses enough of them stops being able to form a cluster
at all, and the symptom is late and unhelpful:

```text
ValueError: [jaccl] Changing queue pair to RTR failed with errno 96
```

By the time errno 96 appears the domains are already gone. This page describes
the accounting that stops a host reaching that state.

## A leaked domain is a leaked process

The domain is held by a **process**, not by damaged kernel state. Measured:
reaping two leaked worker processes changed the next rank start's failure from
errno 96 to `Couldn't connect, error 60` — the domains came back the moment
their owners died.

That is what makes the guard possible. "No rank process is alive" is a
sufficient condition for the domains being available, so it is checked before
every start rather than hoped for.

## Two ways a domain is lost, both now written down

| Event | Cost | Recorded by |
| --- | --- | --- |
| A rank start that fails in `mx.distributed.init()` | one domain per attempt | the link watcher, when its PD guard halts |
| A rank that ignores SIGTERM and is SIGKILLed | one domain | `cluster-detach` |

Both append to a **boot-scoped ledger**, one line per event, naming what spent
what. Read it directly when diagnosing:

```sh
cat "$HOME/Library/Application Support/mlx-cluster/pd-debt"
```

Boot scoping is the whole expiry mechanism. Only entries stamped with the
current boot count, so a reboot — the one event that actually returns a domain —
is the one event that clears the ledger.

**Nothing else clears it, and that is the point.** The kickstart counter it
supplements is session-scoped: a link cycle, a settled rank or a `cluster-join`
all reset it. A boot could therefore lose three domains, forget, lose three
more, without bound, while every guard reported green. The ledger survives all
three resets.

**Every reset settles into the ledger rather than discarding.** The ledger was
originally written only at the cap, so a counter sitting at 1 or 2 when one of
those resets fired was simply deleted and the domains those attempts had already
leaked left no trace — the same unbounded accumulation, one level down.
`pd_debt_settle_counter` now transfers the count at every reset site, so
`rank-kickstarts` means "launched attempts whose cost is not yet in the ledger"
and nothing can launder debt out of the accounting by cycling the link. A
settled rank vindicates exactly one attempt (the one now running, holding its
domain live); every earlier attempt in the counter was superseded by another
kickstart, so it failed, and a failed init leaks whether or not a later one
worked.

## How big the budget actually is

Measured on this hardware, not assumed — `ibv_devinfo -v`:

```text
hca_id: rdma_en2      transport: Thunderbolt (100)
        max_pd:   11
        max_qp:   11
        max_cq:   11
        max_mr:  100
```

**Eleven protection domains per RDMA device.** All three `rdma_en*` devices
report the same, and only the carrier-active one is in play. `max_qp` is also
11, which is consistent with the observed terminal error being errno 96 on
`Changing queue pair to RTR` — QPs run out alongside PDs, from the same budget.

Two things follow, and both matter when someone proposes raising the cap:

- **The upstream "~60 sessions" figure does not describe this device.**
  [ml-explore/mlx#3207](https://github.com/ml-explore/mlx/issues/3207) reports
  exhaustion after ~60 file transfers. That is one reporter's observation about
  a file-transfer workload, with no maintainer confirmation and no measurement
  of the underlying limit; 60 exceeds what this hardware advertises by more than
  fivefold. Do not size a cap against it.
- **Current usage is not observable.** `ibv_devinfo` reports capabilities only —
  there is no counter for domains currently allocated, and no way to release one
  short of a reboot. The ledger exists precisely because the kernel will not
  tell us; a cap therefore has to be conservative under unobservable state.

Against that measurement the default cap of 3 is roughly a quarter of the
device's total, leaving the rest for a healthy session and anything else on the
port. The asymmetry that argues for staying conservative: halting costs degraded
service (the watcher restores standalone serving and the host keeps answering),
while exhausting costs a **mandatory reboot** — and the reason this guard exists
is that a reboot is sometimes not available. Raising the cap does not create
domains; it only spends more of them per episode before the guard notices.

## What happens at the cap

The cap is `programs.mlx.clusterMode.maxKickstarts` — not a separate number.
Both count the same resource, one domain per event, so raising one raises the
other and neither budget can silently exceed the other.

At the cap:

- the link watcher **halts rank starts** and pages, before the kernel runs out
  rather than after errno 96 proves it did;
- `cluster-join` **refuses**, before it tears down standalone serving;
- deleting the halt marker by hand does not buy a retry — the clear is
  re-verified against the ledger and re-halted with
  `cause=manual-clear-rejected`.

The only remedy is a reboot. That is not a policy choice; it is what a
protection domain is.

## Reap before start

Before any rank start, the watcher proves no previous rank process survives. If
one does, it is sent **SIGTERM** and the absence is re-verified; if that cannot
be confirmed, the start is refused and retried on the next tick.

Refusing costs nothing — no distributed init runs, so no domain is spent, and no
attempt is consumed from the guard's budget. Escalating to SIGKILL would cost a
reboot, so the watcher never does it. `cluster-detach` is the one command
allowed to escalate, and it pays for it by writing the loss to the ledger.

The process probe is deliberately three-valued. `pgrep` exits 0 for "matched", 1
for "did not match", and 2 or 127 for "I could not answer". Collapsing those
into `! pgrep …` is what makes a missing binary or a stale pattern read as
"nothing is running" — the one answer that lets a second rank start on top of
the first. An unanswerable probe therefore counts as neither running nor absent,
and every caller fails closed in its own direction.

## Reading a `cluster-detach` result

`cluster-detach` prints the debt in its summary and exits **3** when a reboot is
required before the next join:

```text
  rank       : stopped
  PD debt    : 1/3 leaked this boot (cleared only by a reboot)
```

Exit 3 also covers stale swap. Either way the node is serving-safe; it is the
next `cluster-join` that is gated.

## Related

- [cluster-lifecycle.md](cluster-lifecycle.md) — the `cluster-join` /
  `cluster-detach` contract these guards sit inside.
- `modules/mlx/cluster-rank-pattern.nix` — the single definition of the pattern
  that finds the domain-owning process, and the measurement behind its anchor.
- `tests/test-pd-debt.sh` — the test that fails if any of the above regresses.
- `tests/test-pd-counter-settle.sh` — the test that fails if a counter reset can
  discard leaked domains, pinning both the transfer arithmetic and every call
  site that performs it.
