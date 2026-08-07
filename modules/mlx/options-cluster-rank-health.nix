#
# MLX Module — clustered-mode rank-health tunables (is the rank actually alive?)
#
# Split out of ./options-cluster-resilience.nix purely to keep each file under
# the repo per-file size cap. The option paths are UNCHANGED
# (programs.mlx.clusterMode.*): the module system merges this block with the
# ones in options-cluster.nix, options-cluster-resilience.nix,
# options-cluster-lifecycle.nix, cluster-mode.nix and
# cluster-mode-maintenance.nix. Only `lib` is referenced.
#
# The seam is deliberate. Its sibling file holds LINK timing and repair — how
# long before the cable is believed gone, how hard to try to bring it back.
# This file holds the opposite question: the link is fine, so is the RANK on
# top of it actually working? Both thresholds below exist because a rank told
# the watcher it was healthy when it was not, in two different ways.
#
{ lib, ... }:
{
  options.programs.mlx.clusterMode = {
    warmRecheckSecs = lib.mkOption {
      type = lib.types.int;
      default = 600;
      description = ''
        Soak interval (vk1188): once the automated health gate has passed,
        re-probe liveness this often for as long as the link session is up;
        0 disables the soak. Appends PASS/FAIL evidence to the health-gate
        state file every time it fires.

        Readiness is a one-shot latch, so without a periodic recheck a rank
        that wedges AFTER its first pass (2026-07-25: an 8-token completion
        returning 0 bytes after 900s, both ranks at ~100% CPU) sits for over
        an hour with nothing escalating. A single soak failure halts
        immediately — unlike maxWarmFailures below, which tolerates
        CONSECUTIVE failures of the initial gate, a 10-minute-interval miss
        is already a sustained symptom, not a transient one landing mid-
        generation.
      '';
    };

    rankSettleSecs = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = ''
        How long a rank must stay continuously running before the watcher
        believes it started and clears the PD guard (kickstart count + halt
        markers). 0 = clear as soon as launchd reports it running.

        `state = running` is NOT evidence a rank started. mlx_lm.server reaches
        that state immediately and then sits in the jaccl connect back-off
        (2s + 4s + 8s) before `mx.distributed.init()` throws errno 60 and it
        exits. A watcher tick landing inside that window sees "running" and
        clears the halt — so the guard halts, is cleared by the corpse of the
        very attempt that tripped it, and retries forever.

        Observed 2026-07-25 on the worker: three complete
        halt -> clear -> 3x kickstart cycles back to back, each attempt leaking
        another RDMA protection domain. Since PD exhaustion is reboot-only to
        clear, a defeated guard is strictly worse than no guard — it spends the
        budget while reporting that it is protecting it.

        Must exceed the jaccl back-off; the default leaves ample margin.
      '';
    };

    healthGateTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = ''
        vk1188: bound on one 1-token completion — the automated gate's probe
        (b), and every soak recheck thereafter. Real timeout, not the untimed
        curl the manual gate used to run: a rank that never answers must not be
        able to hold the watcher open indefinitely.
      '';
    };

    healthGateConcurrency = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = ''
        vk1188: N completions fired at once for the gate's probe (c), matching
        the ethos of programs.mlx.proxy.concurrencyLimit — a rank can answer
        one request fine and still fall over the moment real traffic overlaps
        it, which one-at-a-time probing can never catch.
      '';
    };

    healthGateConcurrentTimeoutSecs = lib.mkOption {
      type = lib.types.int;
      default = 180;
      description = ''
        vk1188: bound on EACH of the healthGateConcurrency completions above.
        Longer than healthGateTimeoutSecs because N requests genuinely compete
        for the same rank.
      '';
    };
  };
}
