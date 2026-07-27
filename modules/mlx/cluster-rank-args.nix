#
# MLX Module — clustered rank server command line
#
# Split out of ./cluster-mode.nix at the per-file byte cap (.file-size.yml).
# Pure function of its inputs: the argv the rank launcher execs, with nothing
# resolved at runtime.
#
{
  lib,
  pkgs,
  ncfg,
  uvPythonVersion,
  versions,
}:
let
  # The uvx target, shared with ./cluster-rank-pattern.nix so the pgrep pattern
  # that finds this process is derived from the same string that launches it. A
  # literal here and a literal there is how a reap silently stops matching.
  inherit (import ./cluster-rank-pattern.nix { inherit lib; }) rankEntryPoint;
in
[
  "${pkgs.uv}/bin/uvx"
  # Pin the CPython minor so the coordinator and worker ranks resolve the same
  # mlx ABI (single-source uvPythonVersion; see modules/mlx/default.nix).
  "--python"
  uvPythonVersion
  "--from"
  "mlx-lm==${versions.mlxLm}"
  # mlx + mlx-lm are a lockstep pair (lib/versions.nix): pin mlx explicitly
  # like the normal-mode stack does, instead of riding mlx-lm's transitive
  # floor — otherwise the two ranks can resolve an mlx never validated here.
  "--with"
  "mlx==${versions.mlx}"
  "--with"
  "transformers==${versions.transformers}"
  rankEntryPoint
  "--model"
  ncfg.model
  "--host"
  "127.0.0.1"
  "--port"
  (toString ncfg.httpPort)
]
# Tensor parallelism is the mlx-lm default and emits no flag; --pipeline opts
# OUT of it and only glm4_moe/glm4_moe_lite implement it (see shardingMode).
# The two mlx_lm predicates, verbatim:
#   has_pipelining      = hasattr(model, "model") and hasattr(model.model, "pipeline")
#   has_tensor_parallel = hasattr(model, "shard")
++ lib.optional (ncfg.shardingMode == "pipeline") "--pipeline"
++ ncfg.extraServerArgs
