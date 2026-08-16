# Link-watcher environment contract — the derived-tick-count half.
#
# Split out of ./cluster-watcher-env.nix at the repo per-file size cap, the same
# split-rather-than-exempt move that file itself was created by. Merged straight
# back into the same attrset, so the variables the watcher sees are unchanged.
#
# Every threshold here is configured in SECONDS but the watcher only counts in
# TICKS, so each is rounded UP (integer ceil) against tickIntervalSecs, with a
# floor of one — a window shorter than one tick still means "one confirming
# probe", never zero.
{ ncfg }:
let
  ceilTicks =
    secs:
    let
      ticks = (secs + ncfg.tickIntervalSecs - 1) / ncfg.tickIntervalSecs;
    in
    if ticks < 1 then 1 else ticks;
in
{
  # The link-down settle window, in consecutive failed probes.
  downStrikes = ceilTicks ncfg.linkDownSettleSecs;

  # How often the still-down report repeats. This was a bare `:-20` default
  # inside the script with nothing setting it — so the cadence could not be
  # tuned and, on a node running an older generation, was not applied at all.
  downReportEveryTicks = ceilTicks ncfg.downReportEverySecs;

  # The nominal-tick heartbeat. See heartbeatEverySecs: a healthy watcher
  # writes nothing, so this line's absence is the only signal that the agent
  # has stopped ticking at all.
  heartbeatEveryTicks = ceilTicks ncfg.heartbeatEverySecs;

  # The memory-headroom rung's escalate-to-halt dwell. See
  # options-cluster-memory.nix.
  memHeadroomDwellTicks = ceilTicks ncfg.memHeadroomHaltSecs;
}
