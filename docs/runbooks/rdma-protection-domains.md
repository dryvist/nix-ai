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
