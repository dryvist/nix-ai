# Cluster lifecycle: manual join and detach

`cluster-join` and `cluster-detach` are explicit operator commands for the two-node MLX cluster.
They write their decisions to `~/Library/Logs/mlx-cluster/cluster-lifecycle.log`; no cable event starts or stops a rank.

## Before joining

- Plug in the Thunderbolt cable.
- Ensure both nodes use matching software and cluster configuration, and that the selected model is cached on both nodes.
- Configure `peerSsh` on the coordinator. The coordinator starts the worker's `cluster-join --worker` over SSH.
- If a model is selected on the command line, pass the same `--model` and optional `--pipeline` choice to the coordinator command;
  it forwards those values to the worker.

## Bring the cluster up

Run `cluster-join` on the coordinator. It checks the local node, starts the worker join,
publishes the coordinator's armed state, and waits for both ranks to form.
The worker command runs through the coordinator's configured SSH connection.
The coordinator's result is the cluster result.

Each join runs the gates in this order. J1 also runs again at J9 immediately before a rank can start.

- **Before J1.** Refusal tokens: `model-not-cached` or `model-too-large`.
  Operator action: cache the selected model on both nodes, or choose a model whose shard fits the configured wired budget.
- **J1, PD start gate.** Refusal tokens: `pd-gate-unconfigured`, `rank-alive`,
  `rank-probe-unanswerable`, `device-budget-unverified`, `pd-count-unreadable`, or `pd-reserve`.
  Operator action: correct the budget or reserve configuration; prove no rank remains;
  restore the device/count probe; or reboot this Mac when `pd-reserve` returns exit 3.
- **J2, link preparation.** Refusal tokens: `link-prep-not-ready`. The check is read-only.
  Operator action: run `sudo /nix/var/nix/profiles/system/activate`,
  then retry after the link address is present on a carrier-active port outside `bridge0`.
- **J3, wired ceiling.** Refusal tokens: `wired-ceiling-set-failed`.
  Operator action: check `programs.mlx.clusterMode.wiredLimitMb` and the configured exact-value privilege grant, then retry.
- **J4, swap and quiesce.** The coordinator refuses with `stale-swap` when used swap exceeds `joinSwapThresholdMb`.
  Otherwise it quiesces standalone serving and configured launchd agents.
  Operator action: reboot this Mac before joining when stale swap is reported.
  If a quiesce hook warns, inspect the log and let J5 decide whether resources are available.
- **J5, start room.** Refusal tokens: `rank-start-room-unavailable`; details identify the free-memory or wired-ceiling measurement.
  Operator action: correct shard sizing or the wired ceiling and compositor reserve,
  or free the reported memory. If the detail identifies unreclaimed Metal memory, reboot this Mac before retrying; the command returns 3.
- **J6, arm.** Refusal tokens: `armed-state-write-failed` if the peer state or link state cannot be published.
  Operator action: check the state directory and configured paths,
  then run `cluster-detach` to restore a known down state before retrying.
- **J7, peer poll.** Refusal tokens: `peer-state-unreachable`, `local-software-unavailable`,
  `peer-not-armed`, `generation-mismatch`, `clock-unavailable`, `peer-arm-stale`, or `peer-never-armed`.
  Operator action: restore the SSH and peer-state path, match software and model revisions, and check both clocks.
  Retry only after both nodes can publish a fresh armed state.
- **J8, shared start time.** Refusal tokens: `missed-start-window`.
  Operator action: start a fresh coordinator join after both nodes are ready; do not kickstart either rank by hand.
- **J9, final peer and PD gates.** The J1 PD refusal tokens can recur.
  Peer checks can return the J7 tokens or `peer-armed-at-changed`;
  the timing and launch steps can return `missed-start-window`, `rank-model-write`, or `rank-kickstart-failed`.
  The coordinator rank starts first and publishes `STARTED`; the worker rank waits for it before kickstart.
  The worker refuses `coordinator-start-timeout` or `coordinator-start-mismatch`;
  the coordinator refuses `worker-start-timeout` when the worker does not start within 20 seconds.
  Operator action: resolve the logged reason and retry from J1.
  If the PD gate returns `pd-reserve`, reboot this Mac before retrying.
- **J10, formation.** Refusal tokens: `rank-exited-during-formation`, `coordinator-endpoint-not-formed`,
  `worker-rank-exited-during-formation`, `worker-rank-not-stable`, or `worker-aborted`.
  Operator action: read the lifecycle log on both nodes.
  The failed join runs teardown recovery; resolve the reported rank or endpoint failure before retrying.
- **J11, summary.** `decision=formed` records the link state, wired ceiling, rank process ID,
  and measured PD count. Operator action: exit 0 means formation passed.

`cluster-join` checks model availability before J1.
At J1 and J9 it requires a provable absent rank, a verified device budget, and a readable kernel PD count that leaves the configured reserve.
J4 quiesces before J5 measures room.
J6 arms the node; J7 waits up to `joinTimeoutSecs` for a fresh peer arm;
J8 and J9 align and recheck the shared start; J10 checks the coordinator endpoint or worker rank stability.
Formation sends no completion request.

## Detach the cluster

Run `cluster-detach` on the coordinator.
It tears down the local rank, then runs `cluster-detach --worker` over SSH,
verifies standalone serving with a real completion, checks swap, and prints the measured PD count.
If the coordinator cannot reach the worker, the command logs `REFUSE reason=peer-detach-failed rc=<n>`
and exits 1 for every peer return code except 3.
A worker detach that returns 3 propagates exit 3.
A local swap level above `detachSwapThresholdMb` logs `stale-swap` and exits 3.
Run `cluster-detach` locally on the worker if SSH cannot complete its teardown.

The worker-join result follows the same mapping: the coordinator logs `REFUSE reason=peer-join-failed rc=<n>`
and returns 1 for any nonzero worker result except 3, which is propagated as 3.

Exit 0 means all local teardown checks passed.
Exit 1 means a gate, probe, restore step, or peer operation failed.
Exit 3 means the failed local operation or peer result requires a reboot before retrying; reboot the Mac named by the lifecycle log.
A propagated worker exit 3 identifies the worker as the node that requested reboot.

The teardown order is disarm peer state, stop and verify the rank, read the kernel PD count,
restore the standalone wired ceiling and serving, then write link state `down`.
If the rank cannot be proven absent, teardown leaves serving and link state unchanged.
A nonzero PD count after the rank stops requires a reboot before the next join.

## Links

- [Cluster link truths](cluster-link-truths.md)
- [RDMA protection-domain gate](rdma-protection-domains.md)
- [Cluster observation traps](cluster-observation-traps.md)
- [Manual cleanup after a converge](../../REMOVAL.md)
