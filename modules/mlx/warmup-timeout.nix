# Split out of default.nix purely to keep that file under the repo per-file
# size cap (same reason launchd.nix -> launchd-watchdog.nix and
# cluster-mode.nix -> options-cluster.nix were split).
#
# Derived, not guessed (nix-ai warmup-restart-livelock fix): one deadline is
# shared across every preloaded model, so it scales with
# cfg.proxy.healthCheckTimeout (the documented single-model load ceiling)
# times how many models this host warms, plus a fixed margin for the
# completion request and the proxy-readiness poll. This bounds one cycle's
# length only -- modules/mlx/scripts/mlx-warmup.py bounds the RESTART COUNT,
# the actual livelock fix; see its module docstring.
cfg: lib: cfg.proxy.healthCheckTimeout * (lib.max 1 (builtins.length cfg.preload)) + 60
