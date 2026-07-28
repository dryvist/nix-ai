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
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
    LEDGER = "${src}/modules/mlx/scripts/cluster-pd-ledger.sh";
  } "bash ${src}/tests/test-rank-start-guards.sh && touch $out";

  # THE CHECK THAT FAILS IF RDMA PROTECTION-DOMAIN EXHAUSTION CAN RECUR. Four
  # properties, against the shipped layers sourced in the module's own
  # concatenation order: a start is refused while a previous rank survives; both
  # a SIGKILL and a PD-guard halt are recorded as debt; debt at the cap refuses
  # and halts; and only a reboot settles the ledger — not a link cycle, not a
  # by-hand marker delete, not cluster-join. The test header states what is real,
  # what is stubbed, and why the process probe cannot be the real one here.
  mlx-cluster-pd-debt = pkgs.runCommand "check-mlx-cluster-pd-debt" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
    ];
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
    LEDGER = "${src}/modules/mlx/scripts/cluster-pd-ledger.sh";
    RECORD = "${src}/modules/mlx/scripts/cluster-pd-record.sh";
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
    STATUS = "${src}/modules/mlx/scripts/cluster-rank-status.sh";
    REAP = "${src}/modules/mlx/scripts/cluster-rank-reap.sh";
    GUARDS = "${src}/modules/mlx/scripts/cluster-link-guards.sh";
  } "bash ${src}/tests/test-pd-debt.sh && touch $out";

  # THE CHECK THAT FAILS IF A COUNTER RESET CAN DISCARD LEAKED DOMAINS.
  # mlx-cluster-pd-debt above covers the ledger at the CAP; this covers the hole
  # underneath it. The kickstart counter is session-scoped and four paths reset
  # it, but the ledger was only written at the cap — so a counter at 1 or 2 when
  # a link cycle, a settled rank or cluster-join fired was simply deleted, and
  # the domains those attempts leaked left no trace. That reopened the exact
  # accumulation the ledger closes, one level down. Asserts the transfer
  # arithmetic (including the fail-closed direction, where an unguarded
  # subtraction would compute a NEGATIVE debt and record nothing) AND pins the
  # call sites as source, because a correct function nobody calls passes every
  # behavioural assertion while the defect is fully back.
  mlx-cluster-pd-counter-settle = pkgs.runCommand "check-mlx-cluster-pd-counter-settle" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
    ];
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
    LEDGER = "${src}/modules/mlx/scripts/cluster-pd-ledger.sh";
    RECORD = "${src}/modules/mlx/scripts/cluster-pd-record.sh";
    SETTLE = "${src}/modules/mlx/scripts/cluster-pd-settle.sh";
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
    JOIN = "${src}/modules/mlx/scripts/cluster-join.sh";
    GUARDS = "${src}/modules/mlx/scripts/cluster-link-guards.sh";
  } "bash ${src}/tests/test-pd-counter-settle.sh && touch $out";

  # Boot scoping of the halt marker, split out of the rank-guards test at the 12KB
  # file cap. Unit-tests the halt helpers directly: a halt from a previous boot is
  # dropped (else a cold boot can never form the cluster), a halt from THIS boot
  # stands (the PD guard must not weaken), an unreadable boot time fails closed,
  # and operator prose in the detail text cannot spoof the boot field.
  mlx-cluster-halt-boot-scope = pkgs.runCommand "check-mlx-cluster-halt-boot-scope" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
    ];
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
  } "bash ${src}/tests/test-halt-boot-scope.sh && touch $out";

  # The predicate the pair-wide standdown trusts. Absence of the peer's rendezvous
  # session tears this rank down, so a false negative kills a healthy rank
  # mid-generation. Pins the case an ad-hoc probe got wrong in practice: netstat
  # prints the port BEFORE the state, so a `grep 'ESTABLISHED.*\.PORT'` matches
  # nothing and reports a serving cluster as dead. Also pins CLOSE_WAIT as absent,
  # which is what a SIGKILLed peer leaves behind.
  mlx-cluster-peer-rendezvous = pkgs.runCommand "check-mlx-cluster-peer-rendezvous" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
    ];
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
  } "bash ${src}/tests/test-peer-rendezvous-session.sh && touch $out";

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
      # LAST element, not the head: these agents are launched as
      # `<interpreter> <script>` (clusterMode.appleInterpreter) so that macOS
      # attributes their network access to Apple's stable, always-permitted
      # binary rather than to a Nix store path whose TCC identity dies on every
      # rebuild. The head is therefore /bin/bash, which does not exist in the
      # Linux build sandbox — and is not what this check is about anyway. What
      # must build is the SCRIPT.
      agentExes = map (a: pkgs.lib.last agents.${a}.config.ProgramArguments) [
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

  # RDMA PD guard integrity: the halt is not cleared by a rank that merely
  # reached `state = running`, and halting always restores standalone serving.
  # Mirror-style by necessity (see the test header).
  mlx-cluster-pd-guard-integrity = pkgs.runCommand "check-mlx-cluster-pd-guard-integrity" {
    nativeBuildInputs = [ pkgs.coreutils ];
  } "bash ${src}/tests/test-pd-guard-integrity.sh && touch $out";
}
