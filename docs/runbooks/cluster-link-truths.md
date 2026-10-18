# The cluster: current operating truths

This page records what the manual lifecycle commands measure and what their state files mean.
Use [cluster-lifecycle.md](cluster-lifecycle.md) for the operator procedure,
[rdma-protection-domains.md](rdma-protection-domains.md) for the start reserve,
and [cluster-observation-traps.md](cluster-observation-traps.md) when reading macOS network or process output.

## 0. Read measured fields

An interface flag, address, state file, or endpoint response describes only that measurement.
Read the fields named by the command and its lifecycle log;
do not infer cable carrier from an address, rank health from an endpoint listing, or process absence from a marker file.

`cluster-join` checks link preparation, rank presence, device limits, memory room, peer state, and rank formation as separate gates.
`cluster-detach` verifies rank absence and reads the kernel PD count before it restores standalone serving and writes link state `down`.

## 3. Cluster capacity is the sum of both nodes

The current configured ceilings are 102400 MB per node, about 200 GB aggregate.
A per-node ceiling remains a safety limit for that node; it does not describe the capacity of the formed cluster.
Size each shard against the host where it will run and the compositor reserve configured for that host.

## 4. Reading the machine

[Cluster observation traps](cluster-observation-traps.md) covers carrier versus interface flags, link-address state,
the Thunderbolt Bridge, Local Network Privacy errors, and rank exit status.
Use the lifecycle log to correlate these measurements with the gate that read them.

## 5. Serving truths

- The model endpoint is served by the coordinator rank. A worker endpoint check does not establish coordinator service.
- The join formation check uses the coordinator endpoint or the worker rank's stable launchd state.
  It sends no completion request, so formation alone is not proof that generation works.
- `cluster-detach` verifies standalone restoration with a real completion. A probe URL or restore hook that is missing or fails makes teardown report failure.
- The coordinator join quiesces configured standalone serving before starting the cluster. Arrange any required failover before joining.
- Teardown asks launchd to stop the rank and verifies process absence.
  SIGKILL is the last resort; a stopped process does not prove the kernel PD count is zero or that unreclaimed Metal memory is gone.

## 6. Kernel PD count and the start reserve

The join gate uses the kernel's current `AppleThunderboltRDMAProtectionDomain` count.
It first proves no matching rank process is alive, verifies the device's configured `max_pd` budget, then reads the count.
It refuses if the count is unreadable or if the next rank would reach the reserved threshold.
The gate runs at J1 and again at J9.

The defaults are `devicePdBudget = 11` and `pdReserve = 5`, with the assertion `0 < pdReserve < devicePdBudget`.
The rule is `held + 1 >= budget - reserve` means refuse.
With those defaults, a new rank is allowed only while `held <= 4`.

`ioclasscount` reports a system-wide count across RDMA devices and processes.
The configured maximum is per device, so the system-wide reading can over-count relative to one device.
That is the safe direction: the gate may refuse early, but it does not treat an unknown count as available capacity.
A missing command, malformed output, or `<no such class>` response is unreadable even when the command returns zero.

A rank can own a protection domain while its process is alive.
After process death, the gate still reads the kernel count instead of inferring release from an exit code or a completed signal.
A positive count with no rank process is reported as a warning at join;
if teardown finds any PDs still held after stopping the rank, it returns exit 3 so an operator reboots before the next join.
The count may also include a different process, which is why the system-wide measurement remains part of the decision.

For the gate inputs, raw output handling, and example command results, see [rdma-protection-domains.md](rdma-protection-domains.md).

## 8. State files

The cluster state directory is `~/Library/Application Support/mlx-cluster/`.

| Name | Meaning |
| --- | --- |
| `link-state` | `up` while a node is armed for the cluster; `down` after teardown. |
| `peer-state.json` | The published armed state, arm time, boot, software contract, generation, and timestamp. |
| `ibv-matrix.json` | RDMA device selection data used by the rank launcher. |
| `rank-model` | The model and sharding mode selected by the most recent join; teardown removes it. |
| `quiesced-agents` | Launchd agents recorded for restoration after join teardown. |
| `maintenance-window-task` | State owned by the nix-darwin maintenance window. |
| `bin/` | Generated cluster helper executables. |

`link-state` and `peer-state.json` are reset by join, detach, and the peer-state responder's boot check.
They are coordination records, not proof that a rank is alive or absent; use the process and kernel-count checks for those facts.
