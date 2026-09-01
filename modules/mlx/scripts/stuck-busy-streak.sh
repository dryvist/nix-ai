#!/usr/bin/env bash
# The sibling-control streak rule for the metrics-free wedge page.
#
# Split into its own file, concatenated ahead of mlx-watchdog.sh, for the same
# reason wedge-detect.sh is: tests/test-stuck-busy-streak.sh sources this
# directly and proves the rule without running the rest of the watchdog.
#
# WHY THIS IS A NAMED RULE AND NOT AN INLINE CONDITION
#
# The metrics-free page claims a model "refused every request for N CONSECUTIVE
# checks while a sibling served normally", and on that claim it unloads the
# model. Consecutive has to actually hold, because the healthy sibling is the
# entire argument that this is a slot-accounting wedge rather than saturation.
#
# The first version accrued the streak only on qualifying ticks (model busy AND
# some sibling healthy) and cleared it only for models that had stopped being
# busy. A model that stayed busy while NO sibling was healthy therefore hit
# neither path: the streak did not accrue, but it did not clear either -- it
# FROZE.
#
# So a streak could sit across an arbitrarily long stretch of genuine host-wide
# saturation and then reach the threshold on the next tick that happened to
# have a healthy sibling. The page would report N consecutive checks that were
# not consecutive, and would offer saturation-adjacent evidence as proof that
# this was not saturation -- then unload the model on it.
#
# Holding is the bug. A tick with no healthy sibling has no control, so it
# cannot support the claim; the only sound thing to do with the evidence
# accumulated so far is discard it and start again once a control exists.
# Clearing costs at most a delayed page on a real wedge (the streak rebuilds
# within N ticks of a sibling being healthy), which is strictly better than an
# unload fired on a claim that is not true.
#
# Args: <model_is_busy: yes|no> <a_sibling_is_healthy: yes|no>
# Echoes: accrue | clear
stuck_busy_action() {
  local is_busy="${1:-no}" sibling_healthy="${2:-no}"
  if [ "$is_busy" = "yes" ] && [ "$sibling_healthy" = "yes" ]; then
    printf 'accrue\n'
  else
    printf 'clear\n'
  fi
}
