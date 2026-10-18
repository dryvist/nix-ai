# Manual cleanup after the converge

A Nix converge updates declared configuration. It cannot guarantee that old user launchd jobs are unloaded, legacy state and logs
are deleted, old peer-state is rewritten, or a Thunderbolt interface is administratively up. Run these read-only checks after the
converge and use only the listed user-level fixes.

## 1. Removed launchd jobs

**What:** `dev.mlx-cluster.watcher`, `dev.mlx-cluster.peer-liveness`, `dev.mlx-cluster.prefetch`, and
`dev.mlx-cluster.maintenance-window` must be absent. Only the rank and peer-state jobs remain.

**Why a converge leaves it:** The jobs are owned by separate home-manager and nix-darwin configurations. A converge may remove
their declarations without proving that launchd unloaded a job or that its old plist disappeared.

**Verify:**

```sh
for label in dev.mlx-cluster.watcher dev.mlx-cluster.peer-liveness dev.mlx-cluster.prefetch dev.mlx-cluster.maintenance-window; do
  launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 && printf 'loaded %s\n' "$label"
  ls "$HOME/Library/LaunchAgents/$label.plist" >/dev/null 2>&1 && printf 'plist %s\n' "$label"
done
```

Expected output: no output.

**Fix:**

```sh
for label in dev.mlx-cluster.watcher dev.mlx-cluster.peer-liveness dev.mlx-cluster.prefetch dev.mlx-cluster.maintenance-window; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
```

## 2. Legacy state files

**What:** Remove these from the cluster state directory: `pd-debt`, old `rank-*` files except the kept `rank-model`,
`last-halt-cause`, `standalone-lease`, `link-down-*`, `link-facts-last`, `link-prep-repairs`, `port-reups`, `generation-*`,
`health-gate`, `heartbeat-ticks`, `mem-headroom-refused`, `pd-auto-reboot-last`, `peer-*` except `peer-state.json`,
`serving-quiesced`, `soak-busy-skips`, `maintenance-window-task`, `alerts-undelivered.log`, and `*.tmp`.

The keep set is `bin/` and `signing/` (the signing identity), `ibv-matrix.json`, `link-state`, `peer-state.json`,
`quiesced-agents`, and `rank-model`.

**Why a converge leaves it:** These are files in the user's application-support directory, not declared Nix store paths.
Convergence does not delete them.

**Verify:**

```sh
state="$HOME/Library/Application Support/mlx-cluster"
if [ -d "$state" ]; then
  find "$state" -mindepth 1 -maxdepth 1 -print |
    sed "s#^$state/##" |
    awk 'BEGIN { split("bin ibv-matrix.json link-state peer-state.json quiesced-agents rank-model signing", names)
                 for (i in names) keep[names[i]] = 1 }
         !($0 in keep) { print "STALE " $0; stale = 1 }
         END { if (!stale) print "CLEAN" }'
else
  printf 'MISSING state-dir\n'
fi
```

Expected output: `CLEAN`.

**Fix:**

```sh
state="$HOME/Library/Application Support/mlx-cluster"
find "$state" -mindepth 1 -maxdepth 1 \( \
  -name 'pd-debt' \
  -o \( -name 'rank-*' ! -name 'rank-model' \) \
  -o -name 'last-halt-cause' \
  -o -name 'standalone-lease' \
  -o -name 'link-down-*' \
  -o -name 'link-facts-last' \
  -o -name 'link-prep-repairs' \
  -o -name 'port-reups' \
  -o -name 'generation-*' \
  -o -name 'health-gate' \
  -o -name 'heartbeat-ticks' \
  -o -name 'mem-headroom-refused' \
  -o -name 'pd-auto-reboot-last' \
  -o \( -name 'peer-*' ! -name 'peer-state.json' \) \
  -o -name 'serving-quiesced' \
  -o -name 'soak-busy-skips' \
  -o -name 'maintenance-window-task' \
  -o -name 'alerts-undelivered.log' \
  -o -name '*.tmp' \
\) -exec rm -rf {} +
```

## 3. Old peer-state format

**What:** After the first post-converge detach, the peer-state record must be disarmed and the link state must be down.

**Why a converge leaves it:** The record is runtime state. A Nix change does not rewrite the existing file until the lifecycle
command or the responder's boot check writes it.

**Verify:**

```sh
state="$HOME/Library/Application Support/mlx-cluster"
jq -c '{armed,armed_at}' "$state/peer-state.json"
cat "$state/link-state"
```

Expected output:

```text
{"armed":false,"armed_at":0}
down
```

**Fix:** Run `cluster-detach` on the coordinator after convergence. It detaches the worker over SSH after its own teardown.

## 4. Thunderbolt interface admin state

**What:** A previously detached Thunderbolt interface must be administratively up and report active carrier when the cable is
connected.

**Why a converge leaves it:** Administrative interface state is runtime state and is not reset by Nix convergence.

**Verify:** Replace `enX` with the connected Thunderbolt interface.

```sh
/sbin/ifconfig enX | grep -E 'flags=.*UP|status: active'
```

Expected output includes both an `UP` interface flag and `status: active`.

**Fix:**

```sh
sudo -n /sbin/ifconfig enX up
```

## 5. Old cluster logs

**What:** Remove `cluster-watcher*.log`, `cluster-peer-liveness*.log`, and `cluster-prefetch*.log`. Keep
`~/.config/mlx-cluster/alert-url`.

**Why a converge leaves it:** Logs and the operator-seeded alert URL are user data outside the Nix configuration tree.

**Verify:**

```sh
find "$HOME/Library/Logs/mlx-cluster" -maxdepth 1 -type f \( \
  -name 'cluster-watcher*.log' \
  -o -name 'cluster-peer-liveness*.log' \
  -o -name 'cluster-prefetch*.log' \
\) -print
```

Expected output: no output.

**Fix:**

```sh
logs="$HOME/Library/Logs/mlx-cluster"
rm -f "$logs"/cluster-watcher*.log "$logs"/cluster-peer-liveness*.log "$logs"/cluster-prefetch*.log
```

## Whole-system check

Run this when no rank is running. The launchd listing must contain only the rank and peer-state labels, and the kernel PD count
must be zero.

```sh
launchctl list | awk '$3 ~ /mlx-cluster/ {print $3}'
/usr/sbin/ioclasscount AppleThunderboltRDMAProtectionDomain
```

Expected output:

```text
dev.mlx-cluster.rank
dev.mlx-cluster.peer-state
AppleThunderboltRDMAProtectionDomain = 0
```
