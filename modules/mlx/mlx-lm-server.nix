# Official mlx_lm.server wrapper carrying the in-process L2 memory limit.
# Split from default.nix for the 12 KB file-size gate. The wrapper body lives
# in scripts/mlx-lm-server.sh; this file only supplies its build-time values.
#
# mlx-lm carries the harmony patch rather than being the plain upstream
# release: upstream infers no tool parser for gpt-oss, so its harmony tool
# calls come back as raw markup inside `content` with `tool_calls: null`. See
# mlx-lm-patch.nix for the defect and the patch.
#
# The whole stack now resolves from the Nix store (python-overlay.nix) instead
# of `uv run --with`. uv minted a COMPLETE ~1.4 GB venv per distinct
# resolution, shared nothing between them (hardlink count 1), and never
# evicted one: 328 GB of cache on jevans-mbp against a 62 GB Nix store for the
# entire system. Every live uv process also held a shared lock on that cache,
# so `uv cache prune` could never take the exclusive lock and exited 0 having
# freed nothing — which is how it grew unnoticed.
#
# PROCESS SHAPE CHANGED — read before touching any pgrep/pkill consumer.
# This used to exec `uv run ... python launcher`, giving
# llama-swap -> uv run -> python, THREE pids. It now execs python directly, so
# there are TWO. launchScriptBasename below is still the single source every
# pattern derives from, and it is unchanged, so matchers keyed on it keep
# working; anything keyed on "uv run" does not. See scripts/llama-swap-reap.sh
# for what a silently-unmatched pattern cost last time (#1368).
{
  pkgs,
  cfg,
  versions,
}:
let
  gib = 1024 * 1024 * 1024;

  # mlx (Metal wheel) + harmony-patched mlx-lm + transformers, one atomic set.
  pythonEnv = (import ./python-overlay.nix { inherit pkgs versions; }).withPackages (ps: [
    ps.mlx-lm
  ]);

  launcher = ./scripts/mlx-lm-launch.py;
in
{
  pkg = pkgs.writeShellApplication {
    name = "mlx-lm-server";
    text = builtins.readFile (
      pkgs.replaceVars ./scripts/mlx-lm-server.sh {
        memoryLimitBytes = toString (cfg.memoryHardLimitGb * gib);
        # Empty string when unset; the script leaves the variable unexported
        # rather than passing an empty limit through to mlx.
        cacheLimitBytes =
          if cfg.bufferCacheLimitGb == null then "" else toString (cfg.bufferCacheLimitGb * gib);
        suppressWiredLimit = if cfg.suppressWiredLimit then "1" else "";
        pythonEnv = "${pythonEnv}";
        launcher = "${launcher}";
      }
    );
  };

  # Basename of the in-process launcher this wrapper execs into. Single
  # source that default.nix's modelServerProcessPattern.mlx-lm derives its
  # pgrep/pkill pattern from, so the pattern can never silently drift from
  # what this wrapper actually execs the way it did after this file's
  # mlx-lm-launch.py replaced a direct mlx_lm.server invocation (#1368) —
  # the pattern used to read "/mlx_lm\.server" and nobody updated it, so
  # every pgrep/pkill consumer (llama-swap-launch.sh's old reap,
  # mlx-watchdog.sh, mlx-status.sh, cluster-join.sh's quiesce reap) silently
  # matched nothing for months. See scripts/llama-swap-reap.sh for the
  # measured incident.
  launchScriptBasename = builtins.baseNameOf (toString launcher);
}
