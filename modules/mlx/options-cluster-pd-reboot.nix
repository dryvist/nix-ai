#
# MLX Module — clustered-mode PD-exhaustion auto-reboot tunable
#
# Split out of ./options-cluster.nix purely to keep each file under the repo
# per-file size cap. The option path is UNCHANGED (programs.mlx.clusterMode.*):
# the module system merges this declaration block with the ones in
# options-cluster.nix, options-cluster-lifecycle.nix,
# options-cluster-resilience.nix, options-cluster-rank-health.nix and
# cluster-mode.nix. Only `lib` is referenced here.
#
{ lib, ... }:
{
  options.programs.mlx.clusterMode = {
    pdAutoRebootWindowSecs = lib.mkOption {
      type = lib.types.int;
      default = 21600; # 6h
      description = ''
        Seconds between UNATTENDED reboots the watcher may issue to clear a
        PD-exhaustion halt (cause pd-debt-exhausted or rank-start-failures)
        while the link is up. 0 disables auto-reboot outright, leaving the
        halt-and-alert-only behaviour this repo shipped with originally: a
        human has to notice the alert and reboot by hand. That manual step is
        the interlock the operator's chaos-monkey doctrine bans — cables
        plugged in is supposed to mean clustered, unattended, no exceptions —
        and it cost real cluster downtime on 2026-08-01 sitting on exactly this
        halt with the cable plugged in the whole time.

        THE RATE LIMIT, NOT AN ENABLE FLAG, IS THE SAFETY VALVE. A reboot that
        does not resolve the underlying cause (a genuinely absent or
        misconfigured peer, not merely a slow one) would otherwise repeat on
        every tick, without bound. The marker recording the wall-clock time of
        the last auto-reboot lives beside the watcher's other state markers,
        deliberately NOT in the boot-scoped PD ledger everything else here
        resets on — the entire point is that it must outlive the very reboot
        it is rate-limiting.

        6h is a starting guess, not a measurement: generous enough that a
        genuine transient (peer mid-rebuild, a flaky cable) gets one shot at
        unattended recovery per shift, tight enough that a real fault does not
        sit unaddressed until the next business day. Revisit once this has
        actually fired in production.

        FILEVAULT CAVEAT: a FileVault-enabled host is never auto-rebooted,
        regardless of this setting. fdesetup(8)'s authrestart verb itself
        prompts for the FileVault password, and nix-darwin's cluster-ops
        sudoers grant (security.nix) deliberately stores no credential to
        answer that prompt unattended — feeding one automatically is called
        out there as a separate security decision left to the operator. A
        plain reboot on such a host would instead strand it at the pre-boot
        unlock screen with no SSH, which is worse than staying halted. See
        pd_auto_reboot_if_warranted in cluster-link-guards.sh.
      '';
    };
  };
}
