# Which modules the MLX module is assembled from.
#
# Split out of ./default.nix at the repo per-file size cap — the same
# split-rather-than-exempt move ./cluster-script-layers.nix and the
# options-cluster-* family already made, and for the same reason: the list only
# grows, so the file that holds it must not also hold anything else.
#
# Paths are relative to THIS file, which lives in the same directory as
# ./default.nix, so every entry reads exactly as it did before the split.
#
# Roughly in dependency order: option declarations first (the module system does
# not care, but a reader does), then the config-producing modules that consume
# them.
[
  ./options-renamed.nix
  ./options-proxy.nix
  ./options-server.nix
  ./options-cache.nix
  # How every shell-script launchd agent here is launched. One option, because
  # getting it wrong costs the agent its network access, silently.
  ./options-launch.nix
  ./options-batching.nix
  ./options-judge.nix
  ./options-catalog.nix
  ./options-filters.nix
  ./options-parsers.nix
  ./options-runtime.nix
  ./options-residency.nix
  ./options-cluster.nix
  ./options-cluster-pd-reboot.nix
  ./options-cluster-lifecycle.nix
  ./options-cluster-resilience.nix
  ./options-cluster-selfheal.nix
  ./options-cluster-rank-health.nix
  ./options-cluster-memory.nix
  ./options-cluster-peer-state.nix
  ./assertions.nix
  ./packages.nix
  ./launchd.nix
  ./launchd-watchdog.nix
  ./cluster-mode.nix
  ./cluster-mode-maintenance.nix
  ./peer-liveness.nix
  ./cluster-peer-state.nix
]
