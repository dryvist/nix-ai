# RDMA protection domains: the kernel count gate

The [private docs site](https://docs.jacobpevans.com/d/hosts/ai/rdma-protection-domains/) contains the detailed operational reference.
This page records the source-level budget and the checks used by `cluster-join` and `cluster-detach`.

## Device budget

The configured `devicePdBudget` default is 11.
The active RDMA device must report `max_pd` at least as large as that setting.
The device information also reports `max_qp` and `max_cq`; those pools also constrain a working session.
Check with `ibv_devinfo -v`; the expected fields on the configured hardware are:

```text
max_pd: 11
max_qp: 11
max_cq: 11
```

`pdReserve` defaults to 5 and must satisfy `0 < pdReserve < devicePdBudget`.
The reserve keeps capacity available for a new rank and for the other RDMA resources a session uses.

## Process ownership and measurement

A live rank can own a kernel protection domain through its RDMA client.
Process death releases that client's kernel objects before a zombie is reaped,
but an exit status alone does not establish the current count.
The lifecycle gate proves no matching rank is alive and then reads the kernel count directly.

Run the read-only count command:

```sh
/usr/sbin/ioclasscount AppleThunderboltRDMAProtectionDomain
```

An empty count is reported as:

```text
AppleThunderboltRDMAProtectionDomain = 0
```

Any positive integer is the current system-wide count.
The gate accepts only one line in this exact form.
Missing output, malformed output, a missing executable, or `<no such class>` is unreadable and refuses the join,
even when `ioclasscount` returns exit 0.
The queue-pair and RDMA-family counts are logged for information and do not affect the decision:

```sh
/usr/sbin/ioclasscount AppleThunderboltRDMAQueuePair
/usr/sbin/ioclasscount IORDMAFamilyUC
```

## Start rule

At J1, and again immediately before kickstart at J9, `cluster-join` verifies rank absence,
confirms the configured device budget, and reads the PD count.
It refuses when:

```text
held + 1 >= devicePdBudget - pdReserve
```

With the defaults 11 and 5, this refuses at `held = 5`; a start is allowed only while `held <= 4`.
A positive count below that threshold is logged as a warning when no rank is alive.

The PD count is system-wide across RDMA devices and processes, while `max_pd` is a per-device maximum.
The system-wide count can therefore over-count what is held on the active device.
That is the safe direction: it can refuse early, but it cannot make uncertain capacity look available.

The `pd-gate` log records `PASS` or `REFUSE`, a reason token, held count, budget, reserve, and detail.
Refusal tokens are `pd-gate-unconfigured`, `rank-alive`, `rank-probe-unanswerable`,
`device-budget-unverified`, `pd-count-unreadable`, and `pd-reserve`.
A `pd-reserve` refusal returns exit 3: reboot this Mac before retrying.
If teardown stops the rank but still measures a positive PD count, it also returns exit 3 so an operator reboots before the next join.

## Related

- [Cluster lifecycle](cluster-lifecycle.md) — join and detach gates and exit codes.
- [Cluster link truths](cluster-link-truths.md) — the state files and kernel-count boundary.
