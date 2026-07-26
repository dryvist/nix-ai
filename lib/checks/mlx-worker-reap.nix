# Worker-port reap checks.
#
# Two checks, same shape as mlx-cluster-scripts.nix's build+behavior split:
#   mlx-worker-port-reap-build — forces a real build of the llama-swap-launch
#     exe, the only thing that runs writeShellApplication's checkPhase (bash
#     -n + shellcheck at DEFAULT severity — stricter than the repo-wide
#     --severity=warning sweep). Nothing else in `nix flake check` builds it.
#   mlx-worker-port-reap — replays the 2026-07-26 incident (an orphaned
#     mlx_lm.server worker surviving a proxy restart because it held the
#     worker port, invisible to the old process-pattern reap) against the
#     REAL shipped functions, with lsof/kill faked via the env seam they
#     already expose. See tests/test-worker-port-reap.sh's header for what is
#     real and what is stubbed.
{
  pkgs,
  hmConfig,
  src,
}:
{
  mlx-worker-port-reap-build =
    let
      exe = pkgs.lib.findFirst (
        a: pkgs.lib.hasSuffix "/bin/llama-swap-launch" a
      ) null hmConfig.config.launchd.agents.mlx-model-server.config.ProgramArguments;
    in
    pkgs.runCommand "check-mlx-worker-port-reap-build" { } ''
      test -x "${exe}" || {
        echo "llama-swap-launch not executable: ${exe}" >&2
        exit 1
      }
      touch $out
    '';

  mlx-worker-port-reap = pkgs.runCommand "check-mlx-worker-port-reap" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  } "bash ${src}/tests/test-worker-port-reap.sh && touch $out";
}
