# The watchdog script's assembly order, stated once.
#
# mlx-watchdog is not one file: it is several function-definition files
# concatenated ahead of the driver, so each pure function can be sourced and
# unit-tested on its own (tests/test-wedge-classify.sh,
# tests/test-stuck-busy-streak.sh) without running the watchdog.
#
# That order used to be written out in four places -- mlx-watchdog-pkg.nix plus
# three check derivations that rebuild the same script with fakes on PATH. A
# fourth part was added to the package and not to the checks, and three checks
# died with exit 127 on the now-undefined function. The shipped script and the
# script the checks exercise were free to disagree, which is precisely what a
# check of the shipped script must never be.
#
# So: relative filenames, in order, in one list. Consumers join them to the
# path shape they need -- the package reads them from ./scripts, the checks
# `cat` them out of the flake source.
#
# ORDER IS SIGNIFICANT. Every definition must precede its first caller:
# reap_workers (mlx-watchdog.sh) calls mlx_reap_orphan_ports
# (llama-swap-reap.sh), and the driver calls check_wedge (wedge-detect.sh) and
# stuck_busy_action (stuck-busy-streak.sh). Append new parts ahead of the
# driver, never after it.
[
  "llama-swap-reap.sh"
  "wedge-detect.sh"
  "stuck-busy-streak.sh"
  "mlx-watchdog.sh"
]
