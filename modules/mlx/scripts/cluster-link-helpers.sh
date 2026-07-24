# shellcheck shell=bash
# Cluster link watcher — serving-state helpers.
#
# Concatenated ahead of cluster-link-watcher.sh by the module (split out for
# the per-file size cap). Function definitions only — the CLUSTER_* env the
# bodies read is resolved at call time. Every function here is idempotent and
# safe to re-run, which is what lets the watcher retry an incomplete teardown
# instead of consuming the link-state edge on a swallowed error.

# Idempotent wired-ceiling write through the exact-value sudoers grant.
# No-op when unset or already at the target; returns nonzero on failure.
set_wired_limit() {
  local target="$1" current
  [ -n "$target" ] || return 0
  current="$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo '')"
  [ "$current" = "$target" ] && return 0
  if sudo -n /usr/sbin/sysctl -w "iogpu.wired_limit_mb=$target" > /dev/null 2>&1 &&
    [ "$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null)" = "$target" ]; then
    echo "cluster-link: iogpu.wired_limit_mb=$target"
  else
    echo "cluster-link: WARN failed to set iogpu.wired_limit_mb=$target (sudoers grant missing?)" >&2
    return 1
  fi
}

quiesce_normal_serving() {
  if [ "$CLUSTER_ROLE" = "coordinator" ]; then
    # Unload every normal-mode model; the proxy itself stays up so the
    # restore only needs a re-warm, not a proxy restart. Idempotent.
    curl -fsS -m 60 -X POST "$CLUSTER_NORMAL_PROXY/api/models/unload" || true
  elif [ -n "${CLUSTER_QUIESCE_CMD:-}" ]; then
    sh -c "$CLUSTER_QUIESCE_CMD" || true
  fi
}

# Bring normal serving back. Returns nonzero if it could not, so the caller can
# decline to consume the link-state edge and retry on the next tick.
restore_normal_serving() {
  local uid
  uid="$(id -u)"
  if [ "$CLUSTER_ROLE" = "coordinator" ]; then
    # INC-17071: the warmup one-shot re-warms the preload list by POSTing to
    # llama-swap over loopback, so if the server agent is not loaded the
    # kickstart hits nothing and no-ops SILENTLY -- serving never comes back.
    # cluster-join boots that agent out, so any session that used it left the
    # unattended cable-yank path unable to restore. Bootstrap it first, the
    # same way cluster-detach does, so both paths converge.
    if [ -n "${CLUSTER_SERVER_LABEL:-}" ] &&
      ! launchctl print "gui/$uid/$CLUSTER_SERVER_LABEL" > /dev/null 2>&1; then
      if [ ! -f "${CLUSTER_SERVER_PLIST:-}" ]; then
        echo "cluster-link: WARN $CLUSTER_SERVER_LABEL not loaded and no plist to bootstrap" >&2
        return 1
      fi
      echo "cluster-link: standalone server agent not loaded; bootstrapping"
      if ! launchctl bootstrap "gui/$uid" "$CLUSTER_SERVER_PLIST" > /dev/null 2>&1; then
        echo "cluster-link: WARN failed to bootstrap $CLUSTER_SERVER_LABEL" >&2
        return 1
      fi
    fi
    # Re-warm the declared preload list through the existing warmup one-shot.
    launchctl kickstart -k "gui/$uid/$CLUSTER_WARMUP_LABEL" || true
  elif [ -n "${CLUSTER_RESTORE_CMD:-}" ]; then
    # cluster-restore keeps the labels it could not bootstrap and exits nonzero
    # precisely so a later tick retries them; propagate that.
    sh -c "$CLUSTER_RESTORE_CMD" || return 1
  fi
}
