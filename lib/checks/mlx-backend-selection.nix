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
    # Now assertable, because continuousBatching's default is backend-derived.
    # It used to be a flat `true`, so this guard would have failed every mlx-lm
    # host and had to be deferred; with the default telling the truth, the only
    # way to trip it is an explicit override asking a backend for batching it
    # cannot perform.
    #
    # Why it matters: only the vllm-mlx flag builder emits
    # --continuous-batching. Setting it on mlx-lm yields a SERIAL server whose
    # config claims to batch, which is how a serial tier gets mistaken for a
    # batched one.
    assert
      (c.continuousBatching -> c.modelServerBackend == "vllm-mlx")
      || throw "catalog: continuousBatching is set on ${c.modelServerBackend}, whose flag builder does not emit --continuous-batching, so the setting has no effect on the rendered command while the config reads as batching enabled -- set the backend to vllm-mlx or leave continuousBatching at its derived default.";
    helpers.mkMarker "check-mlx-backend-selection" "MLX backend selection: the selected backend is enabled, and batching is only claimed on a backend that can perform it";
}
