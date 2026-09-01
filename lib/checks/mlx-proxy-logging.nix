# Proxy log-format regression: llama-swap's own request lines must carry a
# timestamp. Upstream defaults logTimeFormat to the empty string, which emits
# lines with client address, path, status and duration but NO time — while the
# MLX servers' interleaved lines ARE timestamped and show only the loopback
# address of the proxy that called them. One side then has identity without
# time and the other time without identity, so a rejection cannot be tied to
# the failure it caused. Full rationale lives on the option itself
# (modules/mlx/options-proxy.nix); this only guards the value.
#
# Its own file rather than an addition to mlx-catalog.nix, which sits 2 bytes
# under the 12,288-byte file-size gate — same reason mlx-model-extra-args.nix
# was split out of mlx.nix.
{ pkgs, hmConfigCatalog }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  mlx-proxy-logging =
    let
      c = hmConfigCatalog.config.programs.mlx;
    in
    assert
      c.proxy.logTimeFormat != ""
      || throw "proxy logging: request lines must carry a timestamp — an empty logTimeFormat restores upstream's untimestamped lines, which cannot be correlated with a failure at a known instant";
    helpers.mkMarker "check-mlx-proxy-logging" "MLX proxy: request lines carry a timestamp and are correlatable";
}
