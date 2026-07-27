# Cluster lifecycle: `cluster-join` / `cluster-detach`

Two `pkgs.writeShellApplication` commands (shipped on PATH on both nodes when
`programs.mlx.clusterMode.enable = true`) that make two-Mac JACCL cluster
bring-up and safe-unplug a single, verifiable step each. They are supervised
front-ends over the link watcher (`modules/mlx/scripts/cluster-link-watcher.sh`)
— they never start a rank themselves; the launchd-owned watcher does that. A
plain-shell rank lacks the macOS Local Network entitlement launchd grants and
dies in JACCL rendezvous with errno 60 (INC-17076).

Both commands are idempotent and safe to re-run. All `CLUSTER_*` configuration
is baked at eval from `programs.mlx.clusterMode`, so the commands need no shell
environment and behave identically on the coordinator and the worker.

## `cluster-join` — bring the cluster up

1. Verify/repair link prep on the local node (own static link IP on a
   carrier-active port that is not enslaved in `bridge0`). Repair is a bounded
   `sudo /nix/var/nix/profiles/system/activate` first (re-runs cluster-link-prep
   idempotently), then a direct granted fallback (`bridge0 deletem` + alias-up on
   the carrier port) if activation does not restore prep — both use only the
   cluster-ops sudoers grants (INC-17067). The activation is time-bounded so an
   unrelated hung activation step cannot wedge bring-up.
2. Pin the cluster wired ceiling **before anything loads**
   (`sysctl -w iogpu.wired_limit_mb=<clusterWiredLimitMb>`). This is the one
   non-negotiable step and hard-fails on error: a shard loaded over a standalone-sized
   ceiling wires out the GUI working set and triggers a WindowServer watchdog
   kill / panic (INC-17076, the 2026-07-12 dual-host panic).
3. Coordinator only: refuse to proceed if `vm.swapusage` used exceeds
   `joinSwapThresholdMb` (default 8000 MB) — loading against stale swap spirals
   to a panic (INC-17075) — then quiesce standalone serving (bootout the server +
   warmup agents, wait for zero `vllm-mlx serve` processes, reap orphans after a
   grace).
4. Clear a stale `rank-halted` PD-guard latch, ensure the watcher agent is
   loaded (bootstrap in the caller's own `gui/$uid` domain if not), then let the
   watcher kickstart the rank.
5. Block (bounded by `joinTimeoutSecs`, default 600 s) until the cluster is
   serving. The coordinator issues **no completion of its own**: the link
   watcher fires exactly one warm generation (request #1) at bring-up and records
   success by creating the `rank-warmed` marker, and join gates on the rank
   process being up **and** that marker present. So the total post-formation
   request count is exactly one, issued by one component — Cycle 2 proved a
   second post-formation request wedges the pipeline (INC-17070). Note the
   contract: the `rank-warmed` marker means "the single warm generation succeeded
   at formation", not "serving is healthy now"; a join re-run against a wedged
   same-session cluster passes on the existing marker by design (zero-probe
   contract), so use `cluster-detach` + rejoin to force a fresh formation. Worker
   role blocks until its rank process is running and stable for `workerStableSecs`
   (60 s).
6. Print a state summary (link, ceiling, rank pid, generation) and exit 0 only
   if every check passed.

## `mlx-cluster-peer-liveness` — the no-progress supervisor

A second launchd agent (`dev.mlx-cluster.peer-liveness`, 60 s tick) runs beside
the watcher. The watcher answers "is the cable in and is a rank process
running?"; this answers "is the mesh producing tokens, and if not, which side
broke?" — because a dead peer and a wedged peer look identical from the
coordinator, which blocks forever in `jaccl::MeshImpl::recv` while `/v1/models`
keeps answering 200.

Operationally, two things to know:

- **It can set `rank-halted`.** That latch is no longer PD-guard-only. When the
  coordinator sees `peerLiveness.strikes` consecutive bounded generations return
  no token, it stops the rank, sets the latch, restores standalone serving and
  pages. Clearing it is unchanged: replug the link, or remove the marker.
- **The worker pages separately, with the traceback.** There is no SSH between
  the nodes, so the coordinator can never read the worker's log. The worker's own
  supervisor reports its rank dying and attaches the exception — which is usually
  the actual cause (e.g. a `shardingMode` mismatch raising `ValueError: The model
  does not support pipelining...`). Correlate the two pages by hostname.

It is deliberately reluctant: real traffic in the rank log, or any ESTABLISHED
connection on the endpoint, suppresses the probe entirely, so a healthy rank
mid-generation is never torn down. At the defaults escalation needs roughly 15
minutes of provably zero tokens. Thresholds are
`programs.mlx.clusterMode.peerLiveness.*`.

## `cluster-detach` — the daily safe-unplug

1. Take the Thunderbolt link admin-down (`ifconfig <port> down`) so both watchers
   observe peer loss and run their up→down teardown, then **verify against live
   state** (bounded by `detachTimeoutSecs`, default 300 s): PD-guard/readiness
   markers actually absent, no `mlx_lm.server` process, and
   `iogpu.wired_limit_mb` equal to the standalone value — never trust the logs.
2. Coordinator only: verify standalone serving actually restored — the proxy answers
   **and** a real completion returns from the primary resident. The watcher's
   restore assumes the standalone agents are still loaded and silently no-ops otherwise
   (INC-17071), so this bootstraps the server agent if needed before probing.
3. If `vm.swapusage` used exceeds `detachSwapThresholdMb` (default 20000 MB),
   print a prominent "stale swap — reboot before next join" warning and exit
   with distinct code **3** so a wrapper can chain a reboot (INC-17075).
4. Print an OK/FAIL summary; nonzero exit on any failed postcondition.

## Zero-click flow: what the watcher does with no human at all

`cluster-join` / `cluster-detach` are the *supervised* front-ends. Plugging or
unplugging the cable is meant to be sufficient on its own, and since 2026-07-25
the watcher enforces the parts a human used to have to get right.

**Start order no longer matters.** A worker whose coordinator had no rank yet
used to kickstart into a rendezvous that did not exist (`[jaccl] Couldn't
connect (error: 60)`), and every failed `mx.distributed.init()` leaks a
**reboot-only** RDMA protection domain — three attempts turned "peer not up yet"
into a mandatory reboot (2026-07-24). Both ranks now hold for a shared
wall-clock boundary and reach distributed init together, inside jaccl's fixed
~15 s connect budget. Domains lost anyway are counted in a boot-scoped ledger,
and a start is refused before the kernel runs out — see
[rdma-protection-domains.md](rdma-protection-domains.md).

**A boot does not produce a usable link.** cluster-link prep runs in root
`postActivation`, before Thunderbolt carrier settles, so it can find no
carrier-active port and address nothing — leaving a rank to die with `Couldn't
bind socket (error: 49)` (EADDRNOTAVAIL). The watcher now requires this host to
hold its own link address before starting a rank, and repairs it in place when it
does not (`linkRepair`; direct granted alias first, bounded `activate` second).

**The halt is not just a file.** The marker records *why* (`cause=...`) beside a
sticky `rank-halt-latched`, so deleting `rank-halted` by hand is a *request*: the
watcher re-verifies the preconditions before the first retry, accepts the clear
(resetting the attempt counter) if they pass, and **re-halts** with
`cause=manual-clear-rejected` naming the still-failing precondition if they do
not. That is how the remaining domains were burned on 2026-07-24, and it can no
longer happen. Sanctioned resets: a real link cycle, or `cluster-join`.

**Unplug is debounced in seconds, not probes.** `linkDownSettleSecs` (default
60 s) converts to consecutive failed probes against `tickIntervalSecs` (default
30 s), rounded up, floor of one, so window and tick cannot drift apart. The
debounce is asymmetric on purpose: "up" is believed at the first reply, "down"
must be earned, because a false down tears the rank down *and* resets the PD
guard — a flapping link could otherwise never accumulate toward a halt.

**A page that reaches nobody still reaches the log.** Halt alerts log their full
text on any non-delivery (no pager configured, encode failure, non-200) and
append it to `alerts-undelivered.log` beside the link-state file.

Tunables — all under `programs.mlx.clusterMode`, each documented at its
declaration in `modules/mlx/options-cluster-resilience.nix`:
`tickIntervalSecs`, `linkDownSettleSecs`, `peerRendezvousProbeTimeoutSecs`,
`linkRepair`, `linkRepairActivateTimeoutSecs`, `warmRecheckSecs`.

## One-click flow

```text
# coordinator and worker, in either order (each blocks on its own postconditions)
cluster-join       # -> cluster serving a frontier model over Thunderbolt
# ... run the window ...
cluster-detach     # -> standalone serving restored, node safe to unplug/sleep/reboot
                   #    exit 3 => reboot before the next cluster-join
```

## Local end-to-end testing before the module ships

These are per-host home-manager packages (all `CLUSTER_*` env is baked at eval
from that host's `programs.mlx.clusterMode`), not flake apps — this flake
exposes no `apps`/`packages`, so `nix run .#cluster-join` does NOT work. Build
the exact per-node binary straight from the consuming nix-darwin host config
with this branch pinned, then run the store path on that node:

```bash
# in the nix-darwin repo; HOST is the coordinator or worker host attr
nix build --print-out-paths \
  "$(nix eval --raw ".#darwinConfigurations.$HOST.config.home-manager.users.$USER.home.packages" \
    --apply 'ps: (builtins.head (builtins.filter (x: (x.name or "") == "cluster-join") ps)).drvPath' \
    --override-input nix-ai path:/abs/path/to/this/worktree)^*"
# then run <out>/bin/cluster-join on that node (nix copy the closure to the
# coordinator if /nix/store is not shared).
```

The commands only mutate live state on a host with `clusterMode` enabled and a
cable present; on any other host the link-prep check fails fast and nothing is
started.

## Grants (nix-darwin `sudoers.d/cluster-ops`)

Used by these commands and already granted: exact-value
`sysctl -w iogpu.wired_limit_mb=<value>`, `/nix/var/nix/profiles/system/activate`,
`ifconfig bridge0 deletem *`, and `ifconfig en[0-9]* up` / `en[0-9]* down`. All
`launchctl` verbs run in the caller's own `gui/$uid` domain and need no sudo.

**Link repair is fully granted and auto-run.** `cluster-join` repairs a lost
link (port re-enslaved in `bridge0` after a reboot) by (1) a bounded
`activation` pass, then (2) a direct fallback that frees the Thunderbolt ports
from `bridge0` and aliases the link IP up on the carrier port. The fallback
`ifconfig <port> alias <ip> <mask> up` **is** covered by the `ifconfig en[0-9]* up`
grant: the sudoers `*` glob spans the alias form's spaces (verified 2026-07-19,
rc=0 on both nodes). The bounded activation matters because a full system
activation can wedge on an unrelated step (observed: a home-manager symlink hung
on a stale mount), which would otherwise block bring-up indefinitely.

## Related

- Issues: nix-ai #1284 (this work), #1283 (watcher state-machine defects),
  #1281 (resident streaming defect).
- Incidents: INC-17067 (link-prep loss), INC-17071 (restore assumes loaded
  agents), INC-17075 (stale-swap spiral), INC-17076 (ceiling skip → watchdog
  kill / errno-60 plain-shell rank).
