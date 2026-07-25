# Cluster shell-script checks: the tests under tests/ and the real concatenated
# script builds. Split out of mlx-cluster.nix (which keeps the compile/env-contract
# fixture) when the combined file crossed the 12KB error ceiling in .file-size.yml —
# same split-rather-than-exempt pattern as modules/mlx/options.
{
  pkgs,
  hmConfigCluster,
  src,
}:
let
  # Records the posted JSON and replays a scripted status code, so the alert()
  # contract can be exercised without a network.
  fakeCurl = pkgs.writeShellScriptBin "curl" (
    builtins.readFile ../../modules/mlx/scripts/alert-payload-fakecurl.sh
  );
in
{
  # alert() Slack contract. Both failure modes it covers are SILENT in
  # production — malformed JSON is rejected as invalid_payload, and a non-200
  # used to vanish under `|| true` — so this is the check that fails if either
  # regresses. cluster-link-helpers.sh is function-definitions-only, so the test
  # sources it without running the watcher. mlx-watchdog.sh carries an identical
  # alert(); keep the two in step.
  mlx-cluster-alert-payload = pkgs.runCommand "check-mlx-cluster-alert-payload" {
    nativeBuildInputs = [
      fakeCurl
      pkgs.jq
      pkgs.gnugrep
    ];
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
  } (builtins.readFile ../../modules/mlx/scripts/alert-payload-test.sh);

  # Rank-start guards: the preconditions that decide whether a rank may start at
  # all, and whether a start attempt may be COUNTED against the RDMA PD guard.
  # Sources the shipped helpers + guards in the module's concatenation order and
  # stubs only the thin wrappers over macOS-only binaries
  # (ifconfig/networksetup/nc/sysctl), so the decisions under test are the real
  # ones. Replays the 2026-07-24 incident: a worker that kickstarted into an
  # absent rank 0, exhausted the guard, and was then un-halted by hand.
  mlx-cluster-rank-guards = pkgs.runCommand "check-mlx-cluster-rank-guards" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
    GUARDS = "${src}/modules/mlx/scripts/cluster-link-guards.sh";
  } "bash ${src}/tests/test-rank-start-guards.sh && touch $out";

  # Builds the three CONCATENATED cluster scripts for real. Nothing else does:
  # `nix flake check` only evaluates packages, and the repo-wide shellcheck check
  # lints each fragment on its own. Only an actual build runs
  # writeShellApplication's checkPhase — bash -n plus shellcheck at DEFAULT
  # severity, which is stricter than that sweep's `--severity=warning`.
  #
  # Concatenation is exactly where the extra strictness earns its keep: a helper
  # shipped to a consumer that never calls it fails as SC2329 (hit 2026-07-25,
  # when one shared link-prep library was handed to cluster-detach, which uses a
  # single function from it). That pressure is what keeps the layers split by
  # actual use — cluster-link-locate.sh / -repair.sh / -guards.sh — instead of one
  # grab-bag with a suppression comment on top.
  mlx-cluster-scripts-build =
    let
      agents = hmConfigCluster.config.launchd.agents;
      agentExes = map (a: builtins.head agents.${a}.config.ProgramArguments) [
        "mlx-cluster-watcher"
        # Concatenates the same helpers, so a helper change must build here too.
        "mlx-cluster-peer-liveness"
      ];
      cliExes = map pkgs.lib.getExe (
        builtins.filter (
          p:
          builtins.elem (p.name or "") [
            "cluster-join"
            "cluster-detach"
          ]
        ) hmConfigCluster.config.home.packages
      );
    in
    pkgs.runCommand "check-mlx-cluster-scripts-build" { } ''
      for exe in ${pkgs.lib.concatStringsSep " " (agentExes ++ cliExes)}; do
        test -x "$exe" || {
          echo "cluster script not executable: $exe" >&2
          exit 1
        }
      done
      touch $out
    '';

  # Peer-liveness state machine, assembling and running the REAL script with
  # launchctl/curl/netstat/ping faked (see the test header for what its fakes
  # still assume about live behaviour). Shipped with #1398 but never wired as a
  # check, so nothing ran it — including when the shared alert()/halt_write
  # helpers it concatenates changed underneath it.
  mlx-cluster-peer-liveness = pkgs.runCommand "check-mlx-cluster-peer-liveness" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.jq
    ];
  } "bash ${src}/tests/test-peer-liveness.sh && touch $out";

  # Link-probe debounce: down is earned over the settle window, up is believed at
  # once. Mirror-style by necessity (see the test header).
  mlx-cluster-link-debounce = pkgs.runCommand "check-mlx-cluster-link-debounce" {
    nativeBuildInputs = [ pkgs.coreutils ];
  } "bash ${src}/tests/test-link-debounce.sh && touch $out";
}
