# shellcheck shell=bash
# Periodic orphan reap — the time-triggered half of llama-swap-reap.sh.
#
# WHY A SECOND CALLER. mlx_reap_orphan_ports already runs on the way up
# (llama-swap-launch.sh), and that covers the common case: the proxy dies,
# launchd's KeepAlive restarts it seconds later, and the reap clears whatever
# the old worker left holding a port. But the reap is START-TRIGGERED, so the
# orphan lives exactly as long as the gap before the next start — and that gap
# is UNBOUNDED whenever the proxy does not come back:
#
#   - `launchctl bootout` (an operator stopping serving, or a fault injection)
#   - KeepAlive disabled / the job removed from the domain
#   - the perf-reclaim kill switch
#
# Measured 2026-07-26: a 16.7 GB orphan survived 94 minutes on a worker port;
# an earlier instance left two more at ~5.3 GB each. That memory is simply gone
# from the host until something reaps it.
#
# The dedicated serving watchdog would have caught this via its own
# reap_workers, but it does not run here: launchd-watchdog.nix gates on
# modelServerBackend == "vllm-mlx" while assertions.nix forces "mlx-lm", so on
# every mlx-lm host that ladder is dead code. This agent is the only reclaim
# path that runs without a proxy start.
#
# WHY IT IS SAFE TO RUN WHILE SERVING. It calls mlx_reap_reparented_only, not
# mlx_reap_orphan_ports. The former kills only holders whose ppid is 1 — i.e.
# processes re-parented to launchd, which is precisely what "outlived its
# parent" means. A live worker sits under llama-swap -> uv run -> python, so
# its ppid is never 1 and it is never a candidate. The distinction is covered
# by tests/test-worker-port-reap.sh, including the case where an orphan and a
# live worker hold adjacent ports and only the orphan dies.
#
# Deliberately NOT gated on "is the proxy running": that check races (the proxy
# can stop between the check and the kill) and would skip the case where the
# proxy is up but an orphan from a PREVIOUS generation still squats a port it
# has not yet tried to bind. The ppid predicate needs no such gate.
set -uo pipefail

# Nothing to protect if the port block is not configured — exit quietly rather
# than tripping the `:?` guards in mlx_reap_ports on a misconfigured host.
if [ -z "${MLX_PORT:-}" ] || [ -z "${MLX_WORKER_PORT_RANGE_START:-}" ] ||
  [ -z "${MLX_WORKER_PORT_COUNT:-}" ]; then
  echo "$(date -u +%FT%TZ) mlx-orphan-reap: port block unset; nothing to do" >&2
  exit 0
fi

mlx_reap_reparented_only || {
  # A holder that survived SIGKILL is a real problem, but exiting non-zero
  # every interval would make launchd log-spam a condition nobody can fix from
  # here. The message above already names the pids.
  echo "$(date -u +%FT%TZ) mlx-orphan-reap: giving up this cycle; will retry" >&2
  exit 0
}
