# shellcheck shell=bash
# cluster-join -- one-shot, idempotent cluster bring-up front-end.
#
# The link watcher already owns the mechanics of forming the cluster (kickstart,
# readiness probe, warm generation). cluster-join is the supervised operator
# entry point that makes bring-up safe and verifiable in one command: it repairs
# link prep, pins the wired ceiling BEFORE any load, quiesces standalone serving on the
# coordinator, then hands the actual rank start to the watcher and BLOCKS until a
# real generation proves the cluster is serving. Safe to re-run at any point.
#
# Ranks are NEVER started here directly: a plain-shell rank lacks the macOS Local
# Network entitlement that launchd grants, so JACCL rendezvous dies with errno 60
# (INC-17076). Only the launchd-owned rank agent may run the rank; this command
# just ensures the watcher is loaded and lets it do the kickstart.
#
# Consumed environment (baked by the launchd/module wiring, mirrors the watcher):
#   CLUSTER_ROLE                coordinator | worker
#   CLUSTER_STATIC_SELF_IP      this node's static link address
#   CLUSTER_STATIC_PEER_IP      peer's static link address
#   CLUSTER_RANK_LABEL          launchd label of the cluster rank agent
#   CLUSTER_WATCHER_LABEL       launchd label of the link watcher agent
#   CLUSTER_WATCHER_PLIST       path to the watcher agent plist (for bootstrap)
#   CLUSTER_STATE_FILE          watcher link-state file (locates the marker dir)
#   CLUSTER_WIRED_LIMIT_MB      optional cluster wired ceiling (exact-value grant)
#   CLUSTER_STANDALONE_WIRED_LIMIT_MB  standalone ceiling (unused here; carried for symmetry)
#   CLUSTER_GENERATION_REPO     GitHub owner/repo whose origin/main is the
#                             deploy source of truth for generation parity
#                             (step 0); drift rebuilds from the remote flake
#                             ref directly; empty disables the preflight
#   CLUSTER_JOIN_SWAP_THRESHOLD_MB  refuse to load above this vm.swapusage used (MB)
#   CLUSTER_JOIN_TIMEOUT_SECS   bound on the block-until-serving wait
#   CLUSTER_QUIESCE_GRACE_SECS  grace before reaping orphaned standalone-serve engines
#   CLUSTER_WORKER_STABLE_SECS  worker: seconds the rank must stay up to pass
#   coordinator only:
#   CLUSTER_NORMAL_PROXY        normal-mode llama-swap base URL (graceful unload)
#   CLUSTER_SERVER_LABEL        normal-mode server (llama-swap) launchd label
#   CLUSTER_WARMUP_LABEL        normal-mode warmup one-shot launchd label
#   CLUSTER_KEEP_RESIDENT       newline-separated command-line substrings; a
#                             `vllm-mlx serve` engine matching any is left
#                             running through the quiesce (standalone keep-
#                             resident backend). Empty = reap every engine.
#   (join consumes the watcher's rank-warmed marker; it issues NO completion of
#    its own, so it needs no cluster endpoint URL or model id)
#   worker only:
#   CLUSTER_QUIESCE_CMD         optional worker-side quiesce hook (run via sh -c)
#
# Grants used (nix-darwin sudoers, cluster-ops): exact-value
# `sysctl -w iogpu.wired_limit_mb=<value>`, `/nix/var/nix/profiles/system/activate`,
# `ifconfig bridge0 deletem *`, and `ifconfig en[0-9]* up` / `en[0-9]* down`.
# All launchctl verbs run in the caller's own gui/$uid domain and need no sudo.
# Link repair uses activation FIRST (idempotent, persistent), then a direct
# fallback (bridge0 deletem + alias-up on the carrier port). The fallback IS
# granted: the `ifconfig en[0-9]* up` glob spans the alias form's spaces --
# `ifconfig <port> alias <ip> <mask> up` matches it (verified 2026-07-19 rc=0).

uid="$(id -u)"
state_dir="$(dirname "$CLUSTER_STATE_FILE")"
mkdir -p "$state_dir"
halt_file="$state_dir/rank-halted"
kicks_file="$state_dir/rank-kickstarts"

fail() {
  echo "cluster-join: FAIL: $*" >&2
  exit 1
}

# --- step 0: nix generation parity preflight --------------------------------
# Every node must run the exact same committed system generation before any
# clustering config begins: mixed generations mean mismatched mlx/JACCL stacks
# on the two ranks — the untestable config-parity variable behind the
# INC-17070 deadlock family. Parity is judged against the shared deploy branch
# (origin main of the flake repo) rather than peer SSH: two nodes both at
# remote HEAD are identical by construction, and a node behind HEAD is healed
# by rebuilding DIRECTLY from the remote flake ref (github:<repo>/<rev>) — no
# local checkout is referenced. Unreachable remote only WARNS (offline joins
# stay possible); a dirty/unstamped local generation always fails.
if [ -n "${CLUSTER_GENERATION_REPO:-}" ]; then
  local_rev="$(/run/current-system/sw/bin/darwin-version --json 2>/dev/null |
    jq -r '.configurationRevision // empty')"
  remote_rev="$(git ls-remote "https://github.com/$CLUSTER_GENERATION_REPO" refs/heads/main 2>/dev/null |
    cut -f1)"
  if [ -z "$local_rev" ]; then
    fail "system generation carries no configurationRevision (dirty or unstamped build) — darwin-rebuild switch from a committed revision before clustering"
  elif [ -z "$remote_rev" ]; then
    echo "cluster-join: WARN generation parity unverified (deploy branch unreachable)" >&2
  elif [ "$local_rev" != "$remote_rev" ]; then
    echo "cluster-join: generation drift (local ${local_rev:0:12} != deploy ${remote_rev:0:12}); auto-healing from remote flake"
    sudo /run/current-system/sw/bin/darwin-rebuild switch \
      --flake "github:$CLUSTER_GENERATION_REPO/$remote_rev" ||
      fail "auto-heal rebuild from github:$CLUSTER_GENERATION_REPO/$remote_rev failed"
    local_rev="$(/run/current-system/sw/bin/darwin-version --json 2>/dev/null |
      jq -r '.configurationRevision // empty')"
    [ "$local_rev" = "$remote_rev" ] ||
      fail "still off deploy HEAD after auto-heal (local ${local_rev:0:12}) — investigate before clustering"
    echo "cluster-join: generation parity restored (${local_rev:0:12})"
  else
    echo "cluster-join: generation parity OK (${local_rev:0:12} = deploy HEAD)"
  fi
fi

# --- step 1: verify/repair link prep on THIS node --------------------------
# Prep is healthy when the node's own static link IP is aliased on a physical
# port that is NOT enslaved in the Thunderbolt bridge (bridge0). Repair is a
# bounded system activation FIRST (re-runs cluster-link-prep idempotently), and
# only if that does not restore prep, a direct granted fallback (see
# repair_link_direct) -- both use nothing but the cluster-ops sudoers grants.
iface_holding_self_ip() {
  /sbin/ifconfig 2>/dev/null | /usr/bin/awk -v ip="$CLUSTER_STATIC_SELF_IP" '
    /^[a-z]/ { dev = $1; sub(/:$/, "", dev) }
    $1 == "inet" && $2 == ip { print dev; exit }
  '
}

link_prep_ok() {
  local dev
  dev="$(iface_holding_self_ip)"
  [ -n "$dev" ] || return 1
  [ "$dev" = "bridge0" ] && return 1
  # port must not be a bridge0 member (re-enslavement is the classic prep loss)
  if /sbin/ifconfig bridge0 2>/dev/null | /usr/bin/grep -qw "member: $dev"; then
    return 1
  fi
  # port must have carrier: cluster-detach admin-downs the link but leaves the
  # alias in place, so a down-but-aliased port looks configured yet cannot
  # rendezvous. Require it up so a rejoin repairs (brings it back up) instead
  # of blocking forever on an unreachable peer.
  case "$(/sbin/ifconfig "$dev" 2>/dev/null)" in
    *"status: active"*) ;;
    *) return 1 ;;
  esac
  return 0
}

# Physical Thunderbolt devices (the cable lands on exactly one; the others are
# uncabled). Same discovery cluster-link-prep uses -- never the service order.
tb_devices() {
  /usr/sbin/networksetup -listallhardwareports \
    | /usr/bin/awk '/^Hardware Port: Thunderbolt [0-9]/{getline; sub(/^Device: /, ""); print}'
}

# Direct, granted link repair for when activation cannot (it can hang on an
# unrelated activation step, or need a second pass to bring a just-freed port
# up). Frees every Thunderbolt port from bridge0 and admin-ups it (no address,
# so no stray route), then aliases this node's link IP on the ONE port that
# shows carrier -- matching link-prep's single-active-port rule so the /24 route
# cannot bind to an uncabled sibling. Uses only granted verbs
# (`ifconfig bridge0 deletem *`, `ifconfig en[0-9]* up`; the alias form rides
# the same space-spanning `en[0-9]* up` grant). Hex netmask avoids a dotted
# quad in a public repo.
repair_link_direct() {
  local dev active=""
  while IFS= read -r dev; do
    [ -n "$dev" ] || continue
    if /sbin/ifconfig bridge0 2>/dev/null | /usr/bin/grep -qw "member: $dev"; then
      sudo -n /sbin/ifconfig bridge0 deletem "$dev" > /dev/null 2>&1 || true
    fi
    sudo -n /sbin/ifconfig "$dev" up > /dev/null 2>&1 || true
  done < <(tb_devices)
  # carrier can take a moment after admin-up; retry briefly.
  for _ in 1 2 3 4 5; do
    active="$(tb_devices | while IFS= read -r dev; do
      case "$(/sbin/ifconfig "$dev" 2>/dev/null)" in
        *"status: active"*) echo "$dev"; break ;;
      esac
    done)"
    [ -n "$active" ] && break
    sleep 2
  done
  [ -n "$active" ] || return 1
  sudo -n /sbin/ifconfig "$active" alias "$CLUSTER_STATIC_SELF_IP" 0xffffff00 up > /dev/null 2>&1 || true
}

if link_prep_ok; then
  echo "cluster-join: link prep OK ($CLUSTER_STATIC_SELF_IP on $(iface_holding_self_ip))"
else
  echo "cluster-join: link prep missing ($CLUSTER_STATIC_SELF_IP not aliased on a free port); repairing via activation"
  # Bound the activation: a full system activation can wedge on an unrelated
  # step (observed 2026-07-19: a home-manager symlink hung on a stale mount),
  # which must not block cluster bring-up forever.
  timeout 150 sudo -n /nix/var/nix/profiles/system/activate > /dev/null 2>&1 || true
  if ! link_prep_ok; then
    echo "cluster-join: activation did not restore link prep; trying direct granted repair"
    repair_link_direct || true
  fi
  if ! link_prep_ok; then
    fail "link prep still broken after activation and direct repair. Is the Thunderbolt cable seated? \
Expected $CLUSTER_STATIC_SELF_IP aliased on a carrier-active Thunderbolt port outside bridge0."
  fi
  echo "cluster-join: link prep repaired ($CLUSTER_STATIC_SELF_IP on $(iface_holding_self_ip))"
fi

# --- step 2: pin the wired ceiling BEFORE anything loads (non-negotiable) ---
# Skipping this step risks a WindowServer watchdog kill (INC-17076).
# A shard loaded over a standalone-sized ceiling wires out the GUI working set and
# panics the host, so a failed apply is a HARD stop, not a warning.
if [ -n "${CLUSTER_WIRED_LIMIT_MB:-}" ]; then
  target="$CLUSTER_WIRED_LIMIT_MB"
  current="$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo '')"
  if [ "$current" = "$target" ]; then
    echo "cluster-join: iogpu.wired_limit_mb already $target"
  elif sudo -n /usr/sbin/sysctl -w "iogpu.wired_limit_mb=$target" > /dev/null 2>&1 &&
    [ "$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null)" = "$target" ]; then
    echo "cluster-join: iogpu.wired_limit_mb=$target"
  else
    fail "could not set iogpu.wired_limit_mb=$target (exact-value sudoers grant missing?). \
Refusing to load a shard over a standalone-sized ceiling."
  fi
fi

# --- step 3: coordinator -- swap guard, then quiesce standalone serving -------------
swap_used_mb() {
  /usr/sbin/sysctl -n vm.swapusage 2>/dev/null | /usr/bin/sed -n 's/.*used = \([0-9][0-9]*\).*/\1/p'
}

if [ "$CLUSTER_ROLE" = "coordinator" ]; then
  used="$(swap_used_mb)"
  used="${used:-0}"
  threshold="${CLUSTER_JOIN_SWAP_THRESHOLD_MB:-8000}"
  if [ "$used" -gt "$threshold" ]; then
    fail "stale swap, reboot recommended (vm.swapusage used ${used}M > ${threshold}M). \
Loading a shard against stale swap spirals to a panic (INC-17075)."
  fi
  echo "cluster-join: swap OK (${used}M used <= ${threshold}M)"

  # Graceful unload first (best effort), then bootout the standalone agents entirely so
  # the shard gets the full machine. The proxy grandchildren can survive a
  # bootout (re-parented, still holding memory), so reap them after a grace.
  # The whole-llama-swap bootout below is unchanged — it IS the panic guard.
  # keep-resident engines (CLUSTER_KEEP_RESIDENT) are standalone agents outside
  # llama-swap, so the bootout and the proxy unload never touch them; only the
  # reap of leftover `vllm-mlx serve` engines must skip them (see standalone_serve_pids).
  curl -fsS -m 30 -X POST "${CLUSTER_NORMAL_PROXY:-}/api/models/unload" > /dev/null 2>&1 || true
  /bin/launchctl bootout "gui/$uid/${CLUSTER_WARMUP_LABEL}" > /dev/null 2>&1 || true
  /bin/launchctl bootout "gui/$uid/${CLUSTER_SERVER_LABEL}" > /dev/null 2>&1 || true
  echo "cluster-join: booted out standalone serving ($CLUSTER_SERVER_LABEL, $CLUSTER_WARMUP_LABEL)"

  # PIDs of `vllm-mlx serve` engines that are NOT keep-resident exempt. An engine
  # whose command line contains any CLUSTER_KEEP_RESIDENT substring is left up.
  standalone_serve_pids() {
    local pid cmd pat exempt
    /usr/bin/pgrep -f 'vllm-mlx serve' 2> /dev/null | while read -r pid; do
      cmd="$(/bin/ps -ww -p "$pid" -o command= 2> /dev/null)"
      exempt=false
      if [ -n "${CLUSTER_KEEP_RESIDENT:-}" ]; then
        while IFS= read -r pat; do
          [ -n "$pat" ] || continue
          case "$cmd" in *"$pat"*)
            exempt=true
            break
            ;;
          esac
        done <<< "$CLUSTER_KEEP_RESIDENT"
      fi
      [ "$exempt" = true ] || printf '%s\n' "$pid"
    done
  }

  grace="${CLUSTER_QUIESCE_GRACE_SECS:-30}"
  deadline=$(($(date +%s) + grace))
  while [ -n "$(standalone_serve_pids)" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "cluster-join: standalone-serve engines still up after ${grace}s; reaping orphans (keep-resident spared)"
      standalone_serve_pids | while read -r pid; do /bin/kill "$pid" > /dev/null 2>&1 || true; done
      sleep 3
      break
    fi
    sleep 2
  done
  if [ -n "$(standalone_serve_pids)" ]; then
    fail "standalone-serve engines still running after reap; memory not freed for the shard"
  fi
  echo "cluster-join: standalone serving quiesced (only keep-resident engines remain)"
elif [ -n "${CLUSTER_QUIESCE_CMD:-}" ]; then
  sh -c "$CLUSTER_QUIESCE_CMD" || true
  echo "cluster-join: ran worker quiesce hook"
fi

# --- step 4: clear a stale halt latch, ensure the watcher is loaded ---------
# The watcher (not this command) starts the rank on its next tick. Clear a stale
# PD-guard halt so it is free to kickstart; a fresh session resets the budget.
if [ -f "$halt_file" ]; then
  rm -f "$halt_file" "$kicks_file"
  echo "cluster-join: cleared stale rank-halted latch"
fi

if /bin/launchctl print "gui/$uid/${CLUSTER_WATCHER_LABEL}" > /dev/null 2>&1; then
  echo "cluster-join: watcher already loaded"
else
  if [ -f "${CLUSTER_WATCHER_PLIST:-}" ]; then
    /bin/launchctl bootstrap "gui/$uid" "$CLUSTER_WATCHER_PLIST" > /dev/null 2>&1 || true
  fi
  /bin/launchctl print "gui/$uid/${CLUSTER_WATCHER_LABEL}" > /dev/null 2>&1 ||
    fail "watcher agent not loaded and could not be bootstrapped ($CLUSTER_WATCHER_PLIST)"
  echo "cluster-join: watcher bootstrapped"
fi

# --- step 5: block until the cluster is actually serving --------------------
timeout="${CLUSTER_JOIN_TIMEOUT_SECS:-600}"
deadline=$(($(date +%s) + timeout))

rank_pid() { /usr/bin/pgrep -f 'mlx_lm.server' 2> /dev/null | head -n1; }

if [ "$CLUSTER_ROLE" = "coordinator" ]; then
  # Zero completions from join. The watcher fires exactly ONE warm generation
  # (request #1) as part of bring-up and records success by creating the
  # rank-warmed marker; join CONSUMES that marker instead of issuing its own
  # probe. Cycle 2 proved a second post-formation request -- join's old probe,
  # request #2 -- wedges the pipeline (INC-17070), so the total post-formation
  # request count must be exactly one, issued by exactly one component. Gate on
  # the rank process being up AND the marker present so a stale marker from a
  # prior session (rank not yet restarted) cannot pass early; the watcher clears
  # rank-warmed on every (re)start, so a fresh formation only trips this once its
  # own warm generation lands.
  warm_marker="$state_dir/rank-warmed"
  echo "cluster-join: waiting up to ${timeout}s for the watcher warm generation (rank-warmed)"
  warm_ok=false
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if /usr/bin/pgrep -f 'mlx_lm.server' > /dev/null 2>&1 && [ -e "$warm_marker" ]; then
      warm_ok=true
      break
    fi
    sleep 5
  done
  "$warm_ok" || fail "watcher warm generation did not complete within ${timeout}s \
(rank-warmed marker absent); cluster not serving. join issues no probe of its own by design."
  echo "cluster-join: watcher warm generation confirmed (rank-warmed present); join issued no completion"
else
  # Worker has no endpoint: require the rank process running and STABLE.
  stable="${CLUSTER_WORKER_STABLE_SECS:-60}"
  echo "cluster-join: waiting up to ${timeout}s for the rank to run and stay up ${stable}s"
  running_since=0
  stable_ok=false
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if /bin/launchctl print "gui/$uid/${CLUSTER_RANK_LABEL}" 2> /dev/null | /usr/bin/grep -q "state = running" &&
      /usr/bin/pgrep -f 'mlx_lm.server' > /dev/null 2>&1; then
      [ "$running_since" -eq 0 ] && running_since="$(date +%s)"
      if [ $(($(date +%s) - running_since)) -ge "$stable" ]; then
        stable_ok=true
        break
      fi
    else
      running_since=0
    fi
    sleep 5
  done
  "$stable_ok" || fail "rank did not run and stay up for ${stable}s within ${timeout}s"
  echo "cluster-join: rank stable for ${stable}s"
fi

# --- step 6: state summary --------------------------------------------------
ceiling="$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo '?')"
rp="$(rank_pid)"
echo "======================================================================"
echo "cluster-join OK ($CLUSTER_ROLE)"
echo "  link       : $CLUSTER_STATIC_SELF_IP on $(iface_holding_self_ip) (peer $CLUSTER_STATIC_PEER_IP)"
echo "  wired ceil : iogpu.wired_limit_mb=$ceiling"
echo "  rank pid   : ${rp:-none}"
if [ "$CLUSTER_ROLE" = "coordinator" ]; then
  echo "  generation : ok (watcher warm-gen consumed; rank-warmed present, no probe by join)"
else
  echo "  generation : n/a (worker rank stable)"
fi
echo "======================================================================"
exit 0
