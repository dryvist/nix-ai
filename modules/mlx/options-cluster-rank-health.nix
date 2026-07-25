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
      default = 1800;
      description = ''
        Re-arm the warm marker after this long, so the post-readiness wedge
        detector can run more than once per link session; 0 disables re-checks.

        Readiness is a one-shot latch and the wedge detector is gated on the
        warm marker being absent, so without this a single successful warm
        disables the detector for the rest of the session — which is how a rank
        that wedged AFTER its first warm (2026-07-25: an 8-token completion
        returning 0 bytes after 900s, both ranks at ~100% CPU) sat for over an
        hour with nothing escalating.

        Deliberately long: mlx_lm.server blocks HTTP during a generation, so a
        healthy rank mid-answer fails a probe, and only maxWarmFailures
        CONSECUTIVE failures escalate.
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
  };
}
