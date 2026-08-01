# RDMA protection-domain guard — the ledger's CALL SITES.
#
# Split out of ./mlx-cluster-pd-env.nix for the per-file size cap, at the seam
# that file already marked. Its sibling pins the guard's PLUMBING: the env vars,
# patterns and paths that reach the scripts. This one pins that somebody still
# CALLS the ledger.
#
# The distinction is the whole reason both exist. tests/test-pd-debt.sh proves
# the ledger functions behave; it cannot prove anyone invokes them. Delete the
# pd_debt_record line from cluster-detach and every one of those assertions
# still passes while a SIGKILLed rank silently stops costing anything — the same
# shape as "a reap that matches nothing looks exactly like nothing to clean up".
#
# Live cluster formation cannot be exercised in CI — and, while the Proxmox
# estate is down, not by hand either — so the wiring is asserted rather than
# observed. These are the cheapest checks that fail when a call site vanishes.
{
  pkgs,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  mlx-cluster-pd-callsites =
    let
      # Read as SOURCE, the same way mlx-cluster.nix reads cluster-join.sh: the
      # invariant is about what is written, and a build artefact cannot show a
      # re-introduced literal as clearly as the file can.
      readScript = f: builtins.readFile (src + "/modules/mlx/scripts/${f}");
      rankScripts = map readScript [
        "cluster-join.sh"
        "cluster-detach.sh"
        "cluster-rank-status.sh"
        "cluster-rank-reap.sh"
        "cluster-link-guards.sh"
        "cluster-link-watcher.sh"
      ];
      joinSrc = readScript "cluster-join.sh";
      detachSrc = readScript "cluster-detach.sh";
      watcherSrc = readScript "cluster-link-watcher.sh";
      inherit (pkgs.lib) hasInfix splitString;
      # Code lines only. Comments legitimately name tests/test-pd-debt.sh, and a
      # guard that fires on prose is a guard the next person weakens instead of
      # obeying.
      codeLines = builtins.filter (l: builtins.match "[[:space:]]*#.*" l == null) (
        builtins.concatMap (splitString "\n") rankScripts
      );
      # "pd-debt" as a filename or bare marker, never as the "pd-debt-exhausted"
      # halt cause — hence the required non-hyphen after it.
      namesLedgerFile = l: builtins.match ".*pd-debt([^-].*)?" l != null;
    in
    assert
      hasInfix "pd_debt_record" detachSrc
      || throw "cluster: cluster-detach must record its SIGKILL as PD debt. It is the only command allowed to spend a protection domain, and an unaudited kill is exactly how debt accumulated invisibly across sessions";
    # The watcher records through pd_debt_settle_counter rather than calling
    # pd_debt_record directly. The wrapper is strictly stronger: it records the
    # same debt AND zeroes the counter in one step, which is what lets every
    # OTHER reset site (link cycle, settled rank, cluster-join) transfer its
    # outstanding attempts instead of deleting them. Recording bare left the
    # counter populated at the cap, so the next reset billed the same attempts
    # twice; recording nothing at all is the original defect this line guards.
    #
    # Asserted on the wrapper name, not on either name, because "the watcher
    # mentions pd_debt_record somewhere" would also be satisfied by a stray
    # comment — and the whole point of these call-site assertions is that they
    # fail when the wiring vanishes.
    assert
      hasInfix "pd_debt_settle_counter" watcherSrc
      || throw "cluster: the watcher must settle the kickstart counter into the ledger — recording the domains its PD-guard halt proves were lost AND zeroing the counter. Otherwise the loss lives only in rank-kickstarts, which a link cycle, a settled rank and cluster-join all reset, so a boot can leak three domains, forget, and leak three more without bound";
    assert
      hasInfix "pd_debt_settle_counter" joinSrc
      || throw "cluster: cluster-join must settle the kickstart counter before it resets the session. Deleting a counter that still holds unrecorded attempts writes a BOOT-scoped loss off against a SESSION-scoped reset — the exact laundering the boot-scoped ledger exists to prevent";
    # Join may SETTLE a count it did not create (above); it may not RECORD a
    # fresh leak of its own. The distinction is the whole reason join was given
    # the write side: it resets the kickstart counter, and discarding attempts
    # that already cost domains is spending, silently. Transferring someone
    # else's count is bookkeeping; calling pd_debt_record directly would be join
    # asserting a leak it has no way to have observed.
    assert
      !(hasInfix "pd_debt_record " joinSrc)
      || throw "cluster: cluster-join must not record a fresh leak of its own. It may settle a counter it did not create (pd_debt_settle_counter), because deleting unrecorded attempts is silent spending — but a command whose only job at the cap is to refuse must not be able to assert a protection-domain loss it never observed";
    assert
      !(builtins.any namesLedgerFile codeLines)
      || throw "cluster: a cluster script spells the PD ledger's filename literally. It has ONE definition (cluster-mode.nix) and arrives as CLUSTER_PD_DEBT_FILE; a second spelling is one typo from a writer and a reader on different files, and is also how the ledger would get named in a marker list the teardown clears";
    # tests/test-pd-auto-reboot.sh proves the function behaves; it cannot prove
    # the watcher still calls it. A PD-exhaustion halt (pd-debt-exhausted or
    # rank-start-failures) whose own alert text says "only a reboot clears
    # this" must not be able to sit waiting for a human again — that is exactly
    # the regression this pins.
    assert
      hasInfix "pd_auto_reboot_if_warranted" watcherSrc
      || throw "cluster: the watcher must call pd_auto_reboot_if_warranted from its halted branch. Without it, a PD-exhaustion halt (pd-debt-exhausted or rank-start-failures) sits waiting for a human to notice the alert and reboot by hand — the manual interlock the operator's chaos-monkey doctrine bans, and the exact gap that cost hours of cluster downtime on 2026-08-01";
    helpers.mkMarker "check-mlx-cluster-pd-callsites" "MLX RDMA protection-domain ledger call sites: detach records its SIGKILL, watcher and join settle the kickstart counter, join never records a leak of its own, and no script spells the ledger path literally";
}
