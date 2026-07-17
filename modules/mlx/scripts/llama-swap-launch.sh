#!/usr/bin/env bash
# llama-swap-launch - reap orphaned engine workers, then exec the proxy.
#
# Why this exists: launchd stops the llama-swap proxy, but the vllm-mlx workers
# it spawned are launched through `uv tool uvx`, which puts the real engine two
# levels down. Those grandchildren survive the stop (re-parented to init) despite
# AbandonProcessGroup=false, and they keep HOLDING THEIR LISTEN PORT. The
# replacement proxy then starts a fresh worker that dies instantly on
# `[Errno 48] address already in use`, so KeepAlive restart-loops forever and the
# proxy answers every completion with 429 while /v1/models still returns 200.
# Observed 2026-07-16: a kickstart left an orphan holding :11439 and the serving
# host was down ~1.5 h with no signal. See Zammad (AI/LLM Serving).
#
# The invariant that makes this safe: llama-swap is the ONLY thing that spawns
# vllm-mlx workers, so at proxy-start time a live worker is by definition an
# orphan of a previous proxy — never one this proxy needs. Reaping here makes
# every start path (boot, KeepAlive restart, kickstart) self-cleaning, which is
# what turns a restart back into an actual remedy.

set -euo pipefail

# pgrep/pkill are called by absolute path because on Darwin nixpkgs' procps is
# Apple's, shipping only ps/sysctl/top/watch — a runtimeInputs dependency would
# resolve to nothing under writeShellApplication's sanitized PATH. Same reason
# mlx-watchdog.sh calls /bin/launchctl by path.
pattern='vllm-mlx serve'

reap() {
  /usr/bin/pgrep -f "$pattern" >/dev/null 2>&1 || return 0

  echo "$(date -u +%FT%TZ) llama-swap-launch: reaping orphaned workers matching '${pattern}'" >&2
  /usr/bin/pkill -f "$pattern" || true

  # Give them a graceful window, then escalate. A wedged engine (the
  # broadcast_shapes batch-scheduler hang) ignores SIGTERM, and it is exactly
  # the case that must not survive into the new proxy's port.
  for _ in $(seq 1 10); do
    /usr/bin/pgrep -f "$pattern" >/dev/null 2>&1 || return 0
    sleep 1
  done

  /usr/bin/pkill -9 -f "$pattern" || true
  sleep 2
}

reap

if /usr/bin/pgrep -f "$pattern" >/dev/null 2>&1; then
  # Never exec into a guaranteed bind failure: exiting non-zero makes launchd
  # retry after ThrottleInterval, which is a real recovery path. Starting anyway
  # would just resume the 429 crash-loop this script exists to prevent.
  echo "$(date -u +%FT%TZ) llama-swap-launch: workers survived SIGKILL, refusing to start" >&2
  exit 1
fi

exec llama-swap "$@"
