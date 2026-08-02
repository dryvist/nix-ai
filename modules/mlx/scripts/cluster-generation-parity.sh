# shellcheck shell=bash
# Nix generation parity — one definition of "is this node running the deployed
# system generation?", shared by cluster-join's preflight and the link watcher's
# periodic drift check.
#
# WHY THIS IS A SHARED LAYER AND NOT A cluster-join DETAIL. On 2026-08-01 this
# node had drifted off the deployed generation, so the activation that aliases
# the Thunderbolt link address had never run. The link sat down for 86 hours with
# the cable seated, and the only component that could have noticed — cluster-join
# — is human-initiated, so nothing noticed. Detection had to move onto a timer,
# and a second copy of the comparison on that timer is how the two answers
# quietly disagree.
#
# Function definitions ONLY, so every consumer concatenates it and resolves the
# CLUSTER_* reads in its own scope at call time.
#
# The HEAL stays in cluster-join, deliberately. A `darwin-rebuild switch` fired
# from a launchd agent can be SIGKILLed mid-activation by the very activation it
# is running (home-manager boots agents out to reload them), and a half-applied
# activation is worse than drift. So the timer path reports and pages; the
# supervised path heals. Tradeoff: correcting drift still needs one cluster-join,
# but drift no longer costs the link — the watcher's link self-heal restores the
# address whether or not the generation is current.
#
# Consumed environment:
#   CLUSTER_GENERATION_REPO  GitHub owner/repo whose origin/main is the deploy
#                          source of truth; empty disables the check
#   CLUSTER_DARWIN_VERSION_BIN  darwin-version path (test seam)
#   CLUSTER_GIT_BIN             git path (test seam)

# The committed revision this system generation was built from, or empty when the
# build was dirty/unstamped.
generation_local_rev() {
  "${CLUSTER_DARWIN_VERSION_BIN:-/run/current-system/sw/bin/darwin-version}" --json 2> /dev/null |
    jq -r '.configurationRevision // empty' 2> /dev/null || true
}

# The deploy branch HEAD, or empty when the remote is unreachable (offline is a
# legitimate state, never a failure).
#
# BOUNDED, because the link watcher calls this on a timer. `git ls-remote` has no
# built-in deadline, and a TCP connect that hangs rather than refuses would stall
# the whole convergence tick — a watchdog that can be blocked by the network it is
# not even watching. A timeout returns empty, which every caller already reads as
# "unverified".
generation_remote_rev() {
  timeout "${CLUSTER_GIT_TIMEOUT_SECS:-20}" \
    "${CLUSTER_GIT_BIN:-git}" ls-remote "https://github.com/$CLUSTER_GENERATION_REPO" refs/heads/main 2> /dev/null |
    cut -f1 || true
}

# ONE machine-readable line, so every consumer renders the SAME facts and none of
# them has to infer:
#
#   state=disabled                          no deploy repo configured
#   state=unstamped local= deploy=<rev>     dirty/unstamped build — never cluster
#   state=unverified local=<rev> deploy=    deploy branch unreachable (offline)
#   state=ok local=<rev> deploy=<rev>       this node is at deploy HEAD
#   state=drift local=<rev> deploy=<rev>    this node is behind/ahead of HEAD
#
# Callers parse with the shell's own field splitting; nothing here contains a
# space, so a consumer never has to guess where a field ends.
generation_parity_fact() {
  local local_rev remote_rev
  if [ -z "${CLUSTER_GENERATION_REPO:-}" ]; then
    printf 'state=disabled local= deploy='
    return 0
  fi
  local_rev="$(generation_local_rev)"
  remote_rev="$(generation_remote_rev)"
  if [ -z "$local_rev" ]; then
    printf 'state=unstamped local= deploy=%s' "$remote_rev"
  elif [ -z "$remote_rev" ]; then
    printf 'state=unverified local=%s deploy=' "$local_rev"
  elif [ "$local_rev" = "$remote_rev" ]; then
    printf 'state=ok local=%s deploy=%s' "$local_rev" "$remote_rev"
  else
    printf 'state=drift local=%s deploy=%s' "$local_rev" "$remote_rev"
  fi
}
