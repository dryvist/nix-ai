# The single definition of the pgrep/pkill pattern that locates a running model
# server. Split out of default.nix at the 12KB file-size gate, same as
# ./worker-env.nix and ./llama-swap-launch-pkg.nix.
#
# Five consumers read this one value (launchd.nix, launchd-watchdog.nix,
# packages.nix, cluster-cli-env.nix -> CLUSTER_STANDALONE_PROCESS_PATTERN, and
# scripts/mlx-status.sh). Fixing it here fixes all of them; patching consumers
# individually is what lets them drift apart again.
#
# The mlx-lm value is DERIVED from mlxLmServer.launchScriptBasename — the same
# path reference that builds the actual launcher — never a hand-typed literal.
# A literal is exactly what silently drifted from the real invocation after
# #1368 moved the worker behind mlx-lm-launch.py: the shipped pattern
# "/mlx_lm\.server" then matched NOTHING against a live worker, so every
# pattern-based reap became a silent no-op. Measured, not argued:
#
#     pgrep -fl '/mlx_lm\.server'    -> NO MATCH   (against a serving worker)
#     pgrep -fl 'mlx-lm-launch\.py'  -> uv supervisor + the real engine
#
# NO leading "/" anchor. The old pattern matched a venv-installed console
# script (".../bin/mlx_lm.server", a real "/" before the name). This script is
# a bare Nix store path interpolation, so its argv is
# ".../store/<hash>-mlx-lm-launch.py" — the character immediately before the
# basename is the store naming convention's "-", never "/". An anchored pattern
# therefore never matches; confirmed against a real running worker rather than
# inferred. A bare substring match is safe because this name is never typed as
# a naked CLI argument anywhere in this codebase — the case the old anchor
# actually guarded against for cluster mode's `uvx ... mlx_lm.server`
# invocation — only ever as a path suffix.
#
# escapeRegex matters: the basename contains a "." which would otherwise be a
# single-character wildcard.
{
  lib,
  cfg,
  mlxLmServer,
}:
{
  modelServerProcessPattern =
    {
      mlx-lm = lib.escapeRegex mlxLmServer.launchScriptBasename;
      vllm-mlx = "vllm-mlx serve";
    }
    .${cfg.modelServerBackend};
}
