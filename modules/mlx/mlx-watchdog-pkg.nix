# Serving watchdog package — split from default.nix (12KB gate), same
# pattern as llama-swap-launch-pkg.nix.
#
# Wedge-detection logic lives in scripts/wedge-detect.sh (function
# definitions only, same split as llama-swap-reap.sh ahead of
# llama-swap-launch.sh) so tests/test-wedge-classify.sh can source it
# directly without running the rest of the watchdog. reap_workers() (in
# mlx-watchdog.sh) calls mlx_reap_orphan_ports from llama-swap-reap.sh
# (nix-ai#1423 — port ownership, not a process pattern), so that file is
# concatenated first here too.
{ pkgs, lib }:
pkgs.writeShellApplication {
  name = "mlx-watchdog";
  runtimeInputs = with pkgs; [
    curl
    coreutils
    gawk
    jq
  ];
  # Parts and their order come from ./watchdog-parts.nix so the shipped script
  # and the script every check exercises cannot drift apart.
  text = lib.concatMapStringsSep "\n" (f: builtins.readFile (./scripts + "/${f}")) (
    import ./watchdog-parts.nix
  );
}
