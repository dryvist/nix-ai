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

1. Verify/repair link prep on the local node (own static link IP aliased on a
   port that is not enslaved in `bridge0`). Repair is a granted, idempotent
   `sudo /nix/var/nix/profiles/system/activate`, which re-runs cluster-link-prep
   — never a hand-rolled reconfig (INC-17067).
2. Pin the cluster wired ceiling **before anything loads**
   (`sysctl -w iogpu.wired_limit_mb=<clusterWiredLimitMb>`). This is the one
   non-negotiable step and hard-fails on error: a shard loaded over a day-sized
   ceiling wires out the GUI working set and triggers a WindowServer watchdog
   kill / panic (INC-17076, the 2026-07-12 dual-host panic).
3. Coordinator only: refuse to proceed if `vm.swapusage` used exceeds
   `joinSwapThresholdMb` (default 8000 MB) — loading against stale swap spirals
   to a panic (INC-17075) — then quiesce day serving (bootout the server +
   warmup agents, wait for zero `vllm-mlx serve` processes, reap orphans after a
   grace).
4. Clear a stale `rank-halted` PD-guard latch, ensure the watcher agent is
   loaded (bootstrap in the caller's own `gui/$uid` domain if not), then let the
   watcher kickstart the rank.
5. Block (bounded by `joinTimeoutSecs`, default 600 s) until the **coordinator
   endpoint returns a real chat completion** (tokens in
   `choices[0].message.content`) — not merely `/v1/models`. Worker role blocks
   until its rank process is running and stable for `workerStableSecs` (60 s).
6. Print a state summary (link, ceiling, rank pid, generation) and exit 0 only
   if every check passed.

## `cluster-detach` — the daily safe-unplug

1. Take the Thunderbolt link admin-down (`ifconfig <port> down`) so both watchers
   observe peer loss and run their up→down teardown, then **verify against live
   state** (bounded by `detachTimeoutSecs`, default 300 s): PD-guard/readiness
   markers actually absent, no `mlx_lm.server` process, and
   `iogpu.wired_limit_mb` equal to the day value — never trust the logs.
2. Coordinator only: verify day serving actually restored — the proxy answers
   **and** a real completion returns from the primary resident. The watcher's
   restore assumes the day agents are still loaded and silently no-ops otherwise
   (INC-17071), so this bootstraps the server agent if needed before probing.
3. If `vm.swapusage` used exceeds `detachSwapThresholdMb` (default 20000 MB),
   print a prominent "stale swap — reboot before next join" warning and exit
   with distinct code **3** so a wrapper can chain a reboot (INC-17075).
4. Print an OK/FAIL summary; nonzero exit on any failed postcondition.

## One-click flow

```text
# coordinator and worker, in either order (each blocks on its own postconditions)
cluster-join       # -> cluster serving a frontier model over Thunderbolt
# ... run the window ...
cluster-detach     # -> day serving restored, node safe to unplug/sleep/reboot
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
