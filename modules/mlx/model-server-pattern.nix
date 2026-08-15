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
#
# COVERS EVERY BACKEND WITH A LIVE WORKER, not just the host default. Since
# programs.mlx.modelBackends made backend selection per-model, one host can run
# workers from more than one backend at once. Keying this on modelServerBackend
# alone regenerated the original defect in a new shape: mlx-watchdog's recovery
# path pkill -f's this pattern, so a worker from a non-default backend survived
# the reap that is supposed to clear a wedged stack, holding its weights wired
# until the proxy restarted. The orphan reap proper (scripts/llama-swap-reap.sh)
# is port-owned and was never affected; this is the watchdog/status path.
{
  lib,
  cfg,
  mlxLmServer,
}:
let
  patterns = {
    mlx-lm = lib.escapeRegex mlxLmServer.launchScriptBasename;
    vllm-mlx = "vllm-mlx serve";
    # uvx runs the module, so argv carries the bare dotted module name.
    mlx-vlm = lib.escapeRegex "mlx_vlm.server";
  };
  backendsInUse = lib.unique ([ cfg.modelServerBackend ] ++ lib.attrValues cfg.modelBackends);
  selected = map (backend: patterns.${backend}) backendsInUse;
in
{
  # Single-backend hosts keep a byte-identical pattern; only a genuinely mixed
  # host pays the alternation. pgrep -f takes an extended regex on macOS.
  modelServerProcessPattern =
    if lib.length selected == 1 then
      lib.head selected
    else
      "(" + lib.concatStringsSep "|" selected + ")";
}
