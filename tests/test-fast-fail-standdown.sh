#!/usr/bin/env bash
# THE TEST THAT FAILS IF A FAST-DYING RANK CAN BURN THE PD BUDGET AGAIN.
#
# THE DEFECT. The pair-wide standdown only reaches a rank that SETTLED
# (CLUSTER_RANK_SETTLE_SECS, default 60). A coordinator hung in distributed init
# ages past that and stands down after three cheap strikes; a worker dies on
# jaccl's ~15s connect budget, well inside a 30s tick, so it is never observed
# running, `rank-started` is never touched, and the standdown is unreachable. It
# fell through to the kickstart counter and paid one protection domain per
# attempt to the cap. Measured 2026-08-07: the worker burned 5 of 11 domains in
# 18 minutes against a coordinator that had already stood down and could never
# answer. Failing fast bought the expensive path; hanging slow bought the cheap
# one. tests/test-pd-counter-settle.sh names this exact shape in prose — this is
# that hole closed.
#
# THE INVARIANT ASSERTED HERE. Two consecutive launched attempts that die before
# settling with no rendezvous session stand the rank down under the SAME
# peer-absent cause the settled path uses — so the same latch, link-cycle re-arm
# and boot-scoped drop apply. One such attempt never latches: a single errno 60
# can be a pure timing miss at the boundary.
#
# ALSO ASSERTED: the strike is errno-aware (rank_failure_stage). A death that
# never got past jaccl's TCP bootstrap (Stage A) cannot have allocated a
# protection domain — ibv_alloc_pd lives in Stage B — so it must not be
# charged against the budget that protects one; a death that reached RDMA
# queue-pair bring-up (Stage B), or an unclassifiable one, still counts. So
# does a stage-a-looking log that PREDATES this attempt (offset at EOF) —
# StandardErrorPath accumulates across restarts, so stale prior-attempt
# output must not be read as this attempt's evidence.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL   — fast_fail_standdown, halt_write and peer_rendezvous_session, sourced
#            from the shipped scripts in the module's own concatenation order.
#   STUB   — sysctl (deterministic boot epoch for the halt marker), netstat (the
#            seam peer_rendezvous_session already exposes), and the three
#            side-effect calls the standdown makes on the host: set_wired_limit,
#            restore_normal_serving, alert. Nothing in the decision is stubbed.
#   SOURCE — part 5 reads the watcher as text. A correct function nobody calls
#            passes every behavioural assertion while the defect is fully back;
#            that is the failure mode this subsystem keeps producing, so the call
#            site is pinned.
#
# Addresses here are RFC 5737 documentation addresses; the predicate under test
# only ever does a substring match, so the real link range is irrelevant to it.
#
# Usage:
#   BOOT_SCOPE=… HELPERS=… GUARDS=… WATCHER=… bash test-fast-fail-standdown.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

halt_file="$state_dir/rank-halted"
latch_file="$state_dir/rank-halt-latched"
strike_file="$state_dir/rank-fast-fails"
started_file="$state_dir/rank-started"

export CLUSTER_ROLE=worker
export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_RENDEZVOUS_PORT=11441
export CLUSTER_ALERT_URL_FILE="$state_dir/alert-url-absent"

# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to cluster-link-helpers.sh}"
# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to cluster-link-guards.sh}"
# The two layers the shipped watcher concatenates AROUND the guards: the
# cross-boot cause budget (rung 0a') and the peer-armed handshake (rung 1e).
# Sourced but left UNCONFIGURED, so both rungs are inert here — the same way
# this file already configures the PD ledger and the memory rung idle. Without
# them the guards would call functions that do not exist, and a `command not
# found` inside an `if !` reads as a refusal, which would silently invert every
# assertion below. Their own behaviour is pinned in tests/test-peer-armed-gate.sh.
# shellcheck disable=SC1090
source "${CAUSE:?set CAUSE to cluster-pd-cause.sh}"
# shellcheck disable=SC1090
source "${PEER_STATE:?set PEER_STATE to cluster-peer-state.sh}"

# --- stubs -------------------------------------------------------------------
sysctl() { echo "{ sec = 1785031601, usec = 0 } stub boottime"; }
hostname() { echo test-host; }

# The netstat seam peer_rendezvous_session already exposes. A shell FUNCTION,
# not a generated script: the nix build sandbox has no /usr/bin/env, so a
# shebang stub silently fails to execute and every case reports "absent" —
# which passes the absent assertions and fails only the present ones. Same
# reasoning as tests/test-peer-rendezvous-session.sh.
netstat_rows=""
fake_netstat() { printf '%s\n' "$netstat_rows"; }
export CLUSTER_NETSTAT_BIN=fake_netstat

# The three host side effects the standdown performs. Recorded, never real.
side_effects="$state_dir/side-effects"
: > "$side_effects"
set_wired_limit() { printf 'wired %s\n' "$1" >> "$side_effects"; }
restore_normal_serving() { printf 'restore\n' >> "$side_effects"; }
alert() { printf 'alert\n' >> "$side_effects"; }

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
reset_state() {
  rm -f "$halt_file" "$latch_file" "$strike_file" "$started_file"
  : > "$side_effects"
  netstat_rows=""
}

# --- 1. one fast fail never latches ------------------------------------------
# A single errno 60 can be a timing miss at the boundary. Latching on it would
# turn one unlucky start into a halt that only a link cycle clears.
reset_state
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 1 "$started_file"; then
  fail "stood down on the FIRST fast fail; the floor of 2 is gone"
fi
[ -f "$halt_file" ] && fail "wrote a halt marker below the floor"
[ "$(cat "$strike_file")" = "1" ] || fail "did not record the first strike"
[ -s "$side_effects" ] && fail "took host side effects below the floor"

# --- 2. the second consecutive fast fail stands the rank down -----------------
if ! fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 2 "$started_file"; then
  fail "did not stand down at the floor; the 5-domain burn is back"
fi
[ -f "$halt_file" ] || fail "stood down without writing the halt marker"
grep -q 'cause=peer-absent' "$halt_file" ||
  fail "halt cause is not peer-absent; the existing latch and link-cycle re-arm no longer apply"
[ "$(cat "$latch_file")" = "peer-absent" ] || fail "latch is not peer-absent"
[ -f "$strike_file" ] && fail "left the strike counter behind after standing down"
grep -q '^restore$' "$side_effects" || fail "did not restore standalone serving"
grep -q '^alert$' "$side_effects" || fail "did not page"

# --- 3. a rank that reached started_file belongs to the settled path ----------
# That path takes its own three rendezvous strikes; double-counting here would
# halt a rank the settled logic is still legitimately evaluating.
reset_state
printf '1\n' > "$strike_file"
touch "$started_file"
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 9 "$started_file"; then
  fail "stood down a rank that had settled; that is the settled path's decision"
fi
[ -f "$strike_file" ] && fail "did not reset the counter once the rank settled"

# --- 4. a live rendezvous session is evidence against the verdict -------------
# netstat prints the port BEFORE the state, so the shipped predicate is
# order-independent; this row keeps that real shape.
reset_state
printf '1\n' > "$strike_file"
netstat_rows="tcp4  0  0  192.0.2.2.49223  192.0.2.1.11441  ESTABLISHED"
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 9 "$started_file"; then
  fail "stood down while the pair was actually rendezvoused"
fi
[ -f "$strike_file" ] && fail "did not reset the counter on a live session"

# --- 4b. no attempt launched yet is nothing to judge --------------------------
reset_state
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 0 "$started_file"; then
  fail "stood down before any attempt was launched"
fi

# --- 4c. a Stage-A death (TCP bootstrap only) is free — it cannot have leaked
# a protection domain ----------------------------------------------------
# ibv_alloc_pd lives in Stage B (RDMA queue-pair bring-up); a rank that only
# ever exhausted jaccl's connect retry loop never reached it. Charging the
# strike budget for a failure that structurally cannot spend it is the exact
# defect under fix.
reset_state
rank_log="$state_dir/cluster-rank.error.log"
export CLUSTER_RANK_ERROR_LOG="$rank_log"
cat > "$rank_log" <<'EOF'
[jaccl] Connection attempt 0 waiting 1000 ms
[jaccl] Connection attempt 1 waiting 2000 ms
[jaccl] Connection attempt 2 waiting 4000 ms
[jaccl] Connection attempt 3 waiting 8000 ms
RuntimeError: [jaccl] Couldn't connect (error: 60)
EOF
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 1 "$started_file"; then
  fail "stood down on a stage-a-only death; it cannot have leaked a domain"
fi
[ -f "$strike_file" ] && fail "counted a stage-a death against the strike budget"
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 2 "$started_file"; then
  fail "stood down after two stage-a-only deaths; still cannot have leaked a domain"
fi
[ -f "$strike_file" ] && fail "counted a second stage-a death against the strike budget"
[ -f "$halt_file" ] && fail "wrote a halt marker for a cause that spends zero domains"

# --- 4d. a Stage-B death (RDMA bring-up actually reached) still floors and
# stands down at 2, unchanged ----------------------------------------------
reset_state
cat > "$rank_log" <<'EOF'
[jaccl] Changing queue pair to RTR failed with errno 96
EOF
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 1 "$started_file"; then
  fail "stood down on the first stage-b strike; the floor of 2 is gone"
fi
[ "$(cat "$strike_file")" = "1" ] || fail "did not count a real stage-b death"
if ! fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 2 "$started_file"; then
  fail "did not stand down at the floor on a real stage-b death"
fi
[ -f "$halt_file" ] || fail "stage-b standdown wrote no halt marker"

# --- 4e. an unclassifiable log still counts — fail closed ------------------
# An unclassifiable failure being treated as free is precisely how a real
# domain leak would go unbounded.
reset_state
cat > "$rank_log" <<'EOF'
some unrelated line matching neither stage's error strings
EOF
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 1 "$started_file"; then
  fail "stood down on the first unclassifiable strike; the floor of 2 is gone"
fi
[ "$(cat "$strike_file")" = "1" ] ||
  fail "an unclassifiable failure must count as a strike, not be treated as free"

# --- 4f. a stage-a-LOOKING log that PREDATES this attempt is stale evidence,
# not this attempt's — classifies unknown and counts -----------------------
# StandardErrorPath accumulates across every rank restart. If THIS attempt
# died leaving no stderr of its own (e.g. SIGKILLed after allocating a
# protection domain, before ever printing an RTR/RTS line), a bare tail would
# still show a PREVIOUS attempt's stage-a lines and wrongly read this one as
# free too. The offset marker — captured at THIS attempt's own kickstart —
# is what tells stale output apart from real evidence.
reset_state
cat > "$rank_log" <<'EOF'
[jaccl] Connection attempt 0 waiting 1000 ms
RuntimeError: [jaccl] Couldn't connect (error: 60)
EOF
offset_file="$state_dir/rank-error-log-offset"
wc -c < "$rank_log" > "$offset_file"
if fast_fail_standdown "$halt_file" "$latch_file" "$strike_file" 1 "$started_file" "$offset_file"; then
  fail "stood down on the first stale-offset strike; the floor of 2 is gone"
fi
[ "$(cat "$strike_file")" = "1" ] ||
  fail "an offset at EOF (nothing appended by this attempt) must count as a strike, not be read as this attempt's stage-a tail"
rm -f "$offset_file"

unset CLUSTER_RANK_ERROR_LOG

# --- 5. the watcher must actually CALL it, ahead of the alignment hold --------
# A correct function nobody calls passes everything above while the defect is
# fully back. And it must sit BEFORE rank_start_preconditions_ok, which contains
# the boundary sleep — a peer that is not coming should cost no wait.
watcher="${WATCHER:?set WATCHER to cluster-link-watcher.sh}"
call_line="$(grep -n 'elif fast_fail_standdown' "$watcher" | head -1 | cut -d: -f1)"
precond_line="$(grep -n 'elif ! rank_start_preconditions_ok' "$watcher" | head -1 | cut -d: -f1)"
[ -n "$call_line" ] || fail "cluster-link-watcher.sh no longer calls fast_fail_standdown"
[ -n "$precond_line" ] || fail "could not locate the precondition branch in the watcher"
[ "$call_line" -lt "$precond_line" ] ||
  fail "fast_fail_standdown runs AFTER the preconditions; the standdown now pays the alignment hold it exists to avoid"
grep -q 'fast_fail_strikes_file' "$watcher" ||
  fail "the link-cycle teardown no longer clears the fast-fail counter"
grep -q 'rank_log_offset_file' "$watcher" ||
  fail "the watcher no longer threads the rank-error-log byte offset through to fast_fail_standdown"

echo "PASS: fast-fail standdown floors at 2, is errno-aware (stage-a free, stage-b/unknown counted, stale offsets fail closed), reuses peer-absent, and is wired ahead of the hold"
