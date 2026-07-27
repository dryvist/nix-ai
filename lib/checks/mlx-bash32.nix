# THE CHECK THAT FAILS IF AN AGENT LAUNCHED BY APPLE'S BASH 3.2 STOPS PARSING
# UNDER IT.
#
# Two halves, because either alone is a check that cannot fail for the reason
# it exists:
#
#   1. The scan. Every shell script this module ships is scanned for the
#      constructs Apple's bash 3.2.57 cannot handle. The one that motivated
#      this — a `case` inside a `$( ... )` — is invisible to every other check
#      in this repo: bash 5 parses it, shellcheck accepts it, and 3.2 fails it
#      at RUNTIME with exit status 0 and a garbage substitution. Two live
#      defects were found by the first run of this scanner:
#        * cluster-link-repair.sh's carrier probe returned the tail of the
#          script instead of a device name (watcher);
#        * llama-swap-reap.sh's `mapfile` was `command not found` under 3.2, so
#          the orphan-port reaper found no holders EVERY time and the orphaned
#          16 GB worker it exists to kill survived (proved in
#          ~/Library/Logs/mlx-model-server/server.error.log).
#
#   2. The scoping guard. The scan is only meaningful for agents actually
#      launched by Apple's interpreter, so this asserts that the model-server
#      agent still is one. (The watcher and peer-liveness agents carry the same
#      assertion in ./mlx-cluster.nix and ./mlx-cluster-peer-env.nix.) Without
#      it, someone could flip the convention off and leave a scan that passes
#      while guarding nothing.
#
# Wired with `&&`, never `cmd; touch $out` — a semicolon would make the marker
# build regardless of the scanner's exit status, i.e. a check that cannot fail.
{
  pkgs,
  hmConfig,
  src,
}:
let
  serverArgs = hmConfig.config.launchd.agents.mlx-model-server.config.ProgramArguments;
in
{
  mlx-bash32-compat =
    assert
      builtins.head serverArgs == "/bin/bash"
      || throw "mlx: the model-server agent must be launched via Apple's /bin/bash (programs.mlx.appleInterpreter) — a Nix interpreter is the responsible process for everything under it and loses its TCC grant on every rebuild; see modules/mlx/options-launch.nix";
    pkgs.runCommand "check-mlx-bash32-compat"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${src}/tests/bash32-scan.py ${src}/modules/mlx/scripts/*.sh \
          && touch $out
      '';
}
