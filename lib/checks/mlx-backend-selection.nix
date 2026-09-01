# Backend-selection contract for the MLX serving catalog.
#
# Split out of ./mlx-catalog.nix to stay under the .file-size.yml ceiling, the
# same reason mlx-wedge-metricsfree.nix is its own file. The split is by
# responsibility: this file asserts WHICH backend may be selected and on what
# terms; mlx-catalog.nix asserts what the selected backend then compiles to.
{ pkgs, hmConfigCatalog }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  mlx-backend-selection =
    let
      c = hmConfigCatalog.config.programs.mlx;
    in
    # These two used to pin the backend to mlx-lm and forbid vllm-mlx outright.
    # Both are now coherence checks rather than a policy pin, because the policy
    # changed: measured at 4-way concurrency on 2026-09-01 the mlx-lm tier
    # queued and stalled rather than batching (16.8s / 21.1s / 79.1s against a
    # ~12s serial baseline, one request never returning), and a stalled request
    # never releases llama-swap's admission slot. Which backend a host runs is
    # that host's decision; what must hold either way is that the selection is
    # coherent.
    assert
      builtins.elem c.modelServerBackend c.enabledBackends
      || throw "catalog: the selected modelServerBackend must be listed in enabledBackends";
    # NOT asserted here, deliberately, and worth knowing why:
    # programs.mlx.continuousBatching DEFAULTS TO TRUE while the mlx-lm flag
    # builder emits no --continuous-batching at all. So today's config reads as
    # "batching on" against a backend that cannot batch, and nothing surfaces
    # the discrepancy -- which is how a serial tier gets mistaken for Lane A.
    # A guard rejecting that combination fails every current mlx-lm host, so it
    # belongs with the fix (make the default backend-aware), not with the change
    # that merely lifts the vllm-mlx deny. Tracked separately.
    helpers.mkMarker "check-mlx-backend-selection"
      "MLX backend selection: the selected backend is enabled, and the batching-default gap is documented where a reader will hit it";
}
