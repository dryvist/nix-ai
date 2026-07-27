# llama-swap proxy launcher — split from default.nix (12KB gate), same
# pattern as mlx-lm-server.nix.
#
# Reaps anything holding our ports (see scripts/llama-swap-reap.sh for why
# port ownership, not process ancestry or a cmdline pattern), then execs
# llama-swap. A worker outliving its proxy keeps its engine port bound, which
# makes every subsequent start fail on bind and answer every completion with
# an HTTP 200 and a zero-byte body forever; reaping on the way up is what
# keeps a restart an actual remedy.
{
  pkgs,
  lib,
  llamaSwapPkg,
}:
pkgs.writeShellApplication {
  name = "llama-swap-launch";
  # No procps: lsof/kill are called by absolute path (see llama-swap-reap.sh)
  # — Darwin's procps ships only ps/sysctl/top/watch, and Darwin's nixpkgs
  # lsof lacks the entitlement Apple's signed system lsof carries to inspect
  # another process's open files.
  runtimeInputs = [
    llamaSwapPkg
    pkgs.coreutils
  ];
  # Reap logic lives in llama-swap-reap.sh (function definitions only, same
  # split as cluster-link-guards.sh ahead of cluster-link-watcher.sh) so
  # tests/test-worker-port-reap.sh can source it directly without the exec at
  # the end of llama-swap-launch.sh.
  text = lib.concatStringsSep "\n" [
    (builtins.readFile ./scripts/llama-swap-reap.sh)
    (builtins.readFile ./scripts/llama-swap-launch.sh)
  ];
}
