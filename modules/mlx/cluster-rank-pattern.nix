# The single definition of the CLUSTER RANK process: the entry point its argv
# names, and the pgrep/pkill pattern that finds the one process holding an RDMA
# protection domain.
#
# THIS IS NOT modelServerProcessPattern, AND THE TWO MUST NEVER BE MERGED.
# They name two different processes:
#
#   standalone (normal mode)  <store>/…-python3-env/bin/python <store>/…-mlx-lm-launch.py
#   cluster rank              uvx  ... mlx_lm.server  ->  <venv>/bin/mlx_lm.server
#
# The standalone line lost its `uv run ...` prefix when normal mode moved to a
# Nix-store python env (modules/mlx/mlx-lm-server.nix): the wrapper now EXECS
# python, so that side is two processes (llama-swap -> python), not three. The
# PATTERNS are unaffected — the standalone one is a bare substring of the
# launcher basename, still present in argv, and the rank one is untouched
# because CLUSTER MODE STILL USES uvx. Both ranks therefore resolve mlx-lm the
# same way as before, so rank-to-rank rendezvous is unchanged by that move.
#
# Note the rank resolves the PLAIN `mlx-lm==<version>` release (see
# ./cluster-rank-args.nix) while standalone resolves the harmony-patched build.
# That divergence PREDATES the Nix migration and is unchanged by it, but it
# means gpt-oss tool calls behave differently in cluster mode.
#
# On develop the two patterns happen to be the same string only because the
# standalone one is stale; the fix for that (deriving it from
# mlxLmServer.launchScriptBasename) makes them diverge. Threading the standalone
# pattern into the cluster call sites would therefore turn every rank reap into a
# permanent silent no-op — the exact class of failure this file exists to close.
#
# MEASURED 2026-07-26, not inferred. The exact invocation from the built
# dev.mlx-cluster.rank plist was run with `--help` (nothing touches RDMA), and
# produced two processes:
#
#   uv tool uvx --python 3.14 --from mlx-lm==… … mlx_lm.server --help
#   …/bin/python …/bin/mlx_lm.server --help
#
# against which live pgrep gave:
#
#   pgrep -f '/mlx_lm\.server'   -> the python engine ONLY   (the PD owner)
#   pgrep -f 'mlx_lm\.server'    -> the engine AND the uvx supervisor
#   pgrep -f 'mlx-lm-launch\.py' -> NO MATCH (rc=1)          (standalone pattern)
#
# THE LEADING "/" IS LOAD-BEARING, and is the opposite of the standalone case.
# uvx passes the entry point as a NAKED CLI ARGUMENT, so its own argv carries the
# bare token; only the resolved console script carries it as a path suffix. An
# unanchored match therefore reports the rank alive after the python child has
# already exited, which blocks a detach forever — and, worse for this
# module, makes a reap-before-start precondition unsatisfiable against a corpse.
#
# escapeRegex matters: the entry point contains a "." that would otherwise be a
# single-character wildcard.
{ lib }:
let
  # The uvx target in ./cluster-rank-args.nix. That file imports this value
  # rather than repeating the literal, so the pattern is derived from the same
  # string that builds the argv and the two cannot drift apart.
  rankEntryPoint = "mlx_lm.server";
in
{
  inherit rankEntryPoint;
  clusterRankProcessPattern = "/" + lib.escapeRegex rankEntryPoint;
}
