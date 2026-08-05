# shellcheck shell=bash
# Worker-port reap — function definitions ONLY (no top-level statements),
# concatenated ahead of llama-swap-launch.sh by
# modules/mlx/llama-swap-launch-pkg.nix, same split as cluster-link-guards.sh
# ahead of cluster-link-watcher.sh. Kept in its own file so
# tests/test-worker-port-reap.sh can source it directly without triggering
# llama-swap-launch.sh's exec.
#
# WHY THIS EXISTS: launchd stops the llama-swap proxy, but mlx_lm.server
# workers it spawned are launched through `uv run`/`uvx`, which puts the real
# engine one or two levels down — a genuine grandchild, confirmed live via
# `ps`: llama-swap -> uv run -> python mlx-lm-launch.py, three distinct PIDs.
# Those descendants survive the stop (re-parented to launchd, ppid 1) despite
# AbandonProcessGroup=false, and they keep HOLDING THEIR LISTEN PORT. The
# replacement proxy's new worker then dies instantly on
# `[Errno 48] address already in use`, llama-swap's health check times out,
# and every completion request hangs for the full timeout and comes back
# HTTP 200 with a ZERO-BYTE body — the worst failure shape here, because it
# looks like success. Measured 2026-07-26: a 16.7 GB, 94-minute-old orphan on
# the worker port; an earlier instance left two more orphans (~5.3 GB each) on
# two different ports. See Zammad (AI/LLM Serving).
#
# THE PREDICATE CHANGED FROM PROCESS PATTERN/ANCESTRY TO PORT OWNERSHIP. A
# prior version of this script pgrep/pkill'd by
# MLX_MODEL_SERVER_PROCESS_PATTERN ("/mlx_lm\.server"). That pattern matches
# the CLUSTER-mode rank invocation (uvx's own installed `mlx_lm.server`
# console script — see cluster-rank-args.nix), but the standalone llama-swap
# worker has, since #1368's in-process L2 memory-limit wrapper, run as
# `mlx-lm-launch.py` instead — a cmdline that never contains that pattern
# text. So the old reap was silently a no-op for every standalone worker:
# confirmed live, 2026-07-26, on a real running worker —
# `pgrep -f '/mlx_lm\.server'` found nothing, `pgrep -f mlx-lm-launch.py`
# found both the `uv run` process and the real engine holding the port.
# Ancestry has the same problem from the other direction: a re-parented
# orphan and a legitimately-detached healthy worker both report PPID 1 (see
# the AbandonProcessGroup comment in launchd.nix), so ancestry cannot tell
# them apart either.
#
# Port ownership does not care what the process looks like or who its parent
# is, so it cannot be broken by the NEXT launcher refactor either. The
# invariant that makes it SAFE is TIMING: this reap is the first thing every
# start path (boot, KeepAlive restart, kickstart) runs for the one launchd
# agent that owns this port block, and it runs strictly before the new proxy
# — or any worker it would spawn — exists. So anything already bound to one
# of these ports right now cannot be a worker of the run that is about to
# start; it can only be a survivor of a previous one. It also cannot be an
# unrelated service: nothing else in this stack binds a port in this block
# (docs/architecture/system-integration-map.md documents 11436+ as the
# mlx_lm.server worker range), and the timing invariant means nothing
# legitimate is listening here yet either.
#
# Consumed environment (baked by modules/mlx/launchd.nix):
#   MLX_PORT                     the proxy's own listen port
#   MLX_WORKER_PORT_RANGE_START  first port llama-swap may hand a worker
#                                (== llama-swap.json's startPort)
#   MLX_WORKER_PORT_COUNT        worker ports to protect: the CURRENT config's
#                                total distinct model count (derived once from
#                                allModels — an overestimate under
#                                programs.mlx.singleModel is safe, an
#                                underestimate would not be)
#   MLX_LSOF_BIN MLX_KILL_BIN    test seams; production absolute paths
#                                (/usr/sbin/lsof, /bin/kill are outside
#                                writeShellApplication's sanitized PATH, and
#                                Darwin's nixpkgs lsof lacks the entitlement
#                                Apple's signed system lsof carries to inspect
#                                another process's open files)

# The exact port block this proxy is about to own: its own listen port, plus
# every worker port llama-swap could hand to a model in the CURRENT config.
# One port per line on stdout.
mlx_reap_ports() {
  local port_start="${MLX_WORKER_PORT_RANGE_START:?MLX_WORKER_PORT_RANGE_START unset}"
  local port_count="${MLX_WORKER_PORT_COUNT:?MLX_WORKER_PORT_COUNT unset}"
  local i
  printf '%s\n' "${MLX_PORT:?MLX_PORT unset}"
  for ((i = 0; i < port_count; i++)); do
    printf '%s\n' "$((port_start + i))"
  done
}

# NO BASH 4 SYNTAX BELOW THIS LINE. This file is concatenated into the
# llama-swap-launch agent, which launchd starts via Apple's /bin/bash 3.2 (the
# TCC convention in modules/mlx/options-launch.nix). `mapfile` is a bash 4
# builtin: under 3.2 it is not "a syntax error you would notice", it is
# `mapfile: command not found` on stderr followed by an EMPTY array — so the
# reaper concluded "nothing is holding our ports" every single time and the
# orphan it exists to kill survived. Confirmed live in
# ~/Library/Logs/mlx-model-server/server.error.log. PID lists are therefore
# carried as newline-delimited STRINGS, not arrays: 3.2 also errors on
# `"${arr[@]}"` / `${#arr[@]}` for an empty array under `set -u`, which
# writeShellApplication always sets. tests/bash32-scan.py fails the build if
# either construct comes back.

# Newline-delimited PID list rendered on one line, for a log message.
mlx_pid_list() {
  printf '%s' "$1" | tr '\n' ' ' | sed 's/ *$//'
}

# Every distinct PID currently bound to one of those ports, one per line.
mlx_port_holders() {
  local lsof_bin="${MLX_LSOF_BIN:-/usr/sbin/lsof}"
  local port
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    "$lsof_bin" -ti ":${port}" 2> /dev/null || true
  done < <(mlx_reap_ports) | sort -un
}

# Reap everything currently bound to our port block. Returns 0 once clear
# (including "nothing was ever holding it" — the common case), 1 if a holder
# survived SIGKILL. Never touches a PID outside mlx_reap_ports's block.
mlx_reap_orphan_ports() {
  local kill_bin="${MLX_KILL_BIN:-/bin/kill}"
  local holders pid
  holders="$(mlx_port_holders)"
  [ -n "$holders" ] || return 0

  echo "$(date -u +%FT%TZ) llama-swap-launch: reaping orphan(s) holding our ports (pid: $(mlx_pid_list "$holders"))" >&2
  for pid in $holders; do
    "$kill_bin" -TERM "$pid" 2> /dev/null || true
  done

  # Give them a graceful window, then escalate. A wedged engine (the
  # broadcast_shapes batch-scheduler hang) ignores SIGTERM, and it is exactly
  # the case that must not survive into the new proxy's port.
  for _ in $(seq 1 10); do
    holders="$(mlx_port_holders)"
    [ -n "$holders" ] || return 0
    sleep 1
  done

  echo "$(date -u +%FT%TZ) llama-swap-launch: escalating to SIGKILL (pid: $(mlx_pid_list "$holders"))" >&2
  for pid in $holders; do
    "$kill_bin" -KILL "$pid" 2> /dev/null || true
  done
  sleep 2

  holders="$(mlx_port_holders)"
  [ -n "$holders" ] || return 0
  echo "$(date -u +%FT%TZ) llama-swap-launch: port(s) still held after SIGKILL (pid: $(mlx_pid_list "$holders"))" >&2
  return 1
}
