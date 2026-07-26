# Worker-port reap checks.
#
# mlx-model-server-pattern-matches-launcher is the regression guard for the
# root cause, not just the symptom: modelServerProcessPattern.mlx-lm
# (default.nix) is now derived from mlxLmServer.launchScriptBasename
# (mlx-lm-server.nix) instead of a hand-typed literal -- a hand-typed literal
# is exactly what silently drifted from the real invocation once #1368
# introduced mlx-lm-launch.py. This check proves the derivation actually
# lands where it must: grepping the pattern against the REAL built
# mlx-lm-server launcher script (tests/test-mlx-model-server-pattern.sh).
#
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

  mlx-model-server-pattern-matches-launcher =
    let
      mlxLmServerExe = pkgs.lib.findFirst (
        p: (p.name or "") == "mlx-lm-server"
      ) null hmConfig.config.home.packages;
      pattern =
        hmConfig.config.launchd.agents.mlx-model-server.config.EnvironmentVariables.MLX_MODEL_SERVER_PROCESS_PATTERN;
    in
    pkgs.runCommand "check-mlx-model-server-pattern-matches-launcher" {
      nativeBuildInputs = [ pkgs.gnugrep ];
      MLX_MODEL_SERVER_PATTERN = pattern;
      MLX_LM_SERVER_EXE = "${mlxLmServerExe}/bin/mlx-lm-server";
    } ''
      # `&&`, never `;`. With a semicolon `touch $out` runs even when the test
      # exits non-zero, so the derivation succeeds and the check can never
      # fail — a guard that always passes is worse than no guard, because it
      # reports coverage it does not have. That is the same silent-no-op shape
      # this very check exists to catch.
      bash ${src}/tests/test-mlx-model-server-pattern.sh && touch $out
    '';
}
