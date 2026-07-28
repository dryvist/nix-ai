# RDMA protection-domain guard — env-wiring contract.
#
# Split out of ./mlx-cluster.nix for the per-file size cap, the same seam as
# ./mlx-cluster-peer-env.nix. What it pins is a category of its own: every input
# to the guard that makes protection-domain exhaustion structurally impossible.
#
# THIS IS THE FILE THAT FAILS WHEN THE GUARD IS SILENTLY DISABLED. That failure
# mode is not hypothetical here — it is the subsystem's most repeated defect:
#
#   * sysctl resolved off a writeShellApplication PATH, so every halt recorded
#     boot='unknown', every halt was dropped as stale, and the PD guard did
#     nothing while reporting that it was protecting the budget;
#   * a model-server process pattern that drifted from the real launcher, so a
#     pattern-based reap matched NOTHING for months and "no match" was
#     indistinguishable from "nothing to clean up".
#
# Both were absent or wrong CONFIGURATION reaching a correct script, so this
# check asserts the configuration and not the script. Every value below has a
# script-side `:-default` behind it; a missing one does not crash, it quietly
# reverts the guard to a weaker version of itself.
{
  pkgs,
  hmConfigCluster,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  mlx-cluster-pd-env =
    let
      agents = hmConfigCluster.config.launchd.agents;
      watcher = agents.mlx-cluster-watcher.config;
      watcherEnv = watcher.EnvironmentVariables;
      rankArgs = agents.mlx-cluster-rank.config.ProgramArguments;
      cliEnvs = map (p: p.name or "") hmConfigCluster.config.home.packages;
      # Every script allowed to look for the rank process. Read as SOURCE, the
      # same way mlx-cluster.nix reads cluster-join.sh: the invariant is about
      # what is written, and a build artefact cannot show a re-introduced literal
      # as clearly as the file can.
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
    # The rank pattern must be the ANCHORED entry point, and it must be the
    # entry point that is actually in the rank argv. Measured 2026-07-26 against
    # the real invocation: the resolved console script carries the token as a
    # path suffix while the uvx supervisor carries it as a naked argument, so the
    # leading "/" is what separates the process that owns the protection domain
    # from its parent. Drop the anchor and a reap latches onto the wrapper; drop
    # the derivation and the pattern outlives the entry point it names.
    assert
      watcherEnv.CLUSTER_RANK_PROCESS_PATTERN == "/mlx_lm\\.server"
      || throw "cluster: the rank process pattern must be the anchored entry point '/mlx_lm\\.server'. Unanchored also matches the uvx supervisor (which owns no protection domain); a stale one matches nothing at all, and a reap that matches nothing is indistinguishable from a reap with nothing to do";
    assert
      builtins.elem (builtins.replaceStrings [ "/" "\\" ] [ "" "" ]
        watcherEnv.CLUSTER_RANK_PROCESS_PATTERN
      ) rankArgs
      || throw "cluster: the rank process pattern must name the entry point that is actually in the rank argv — both come from modules/mlx/cluster-rank-pattern.nix so they cannot drift, and this pins that they still do";
    # NO INLINE LITERAL, ANYWHERE. Five copies of '/mlx_lm\.server' used to be
    # hardcoded across cluster-join.sh and cluster-detach.sh while a single
    # derived definition sat unused beside them. That is how a pattern goes stale
    # in one place and not another, and a stale pattern is a reap that silently
    # does nothing. Every lookup now goes through CLUSTER_RANK_PROCESS_PATTERN.
    assert
      builtins.all (s: builtins.match ".*-f '/mlx_lm.*" s == null) rankScripts
      || throw "cluster: a cluster script hardcodes the rank pattern again (`-f '/mlx_lm…`). It has ONE definition, modules/mlx/cluster-rank-pattern.nix, threaded in as CLUSTER_RANK_PROCESS_PATTERN — an inline copy is a pattern that can go stale on its own, and a pgrep that matches nothing looks exactly like nothing to clean up";
    assert
      watcherEnv.CLUSTER_PGREP_BIN == "/usr/bin/pgrep" && watcherEnv.CLUSTER_KILL_BIN == "/bin/kill"
      || throw "cluster: pgrep and kill must arrive as absolute paths — /usr/bin and /bin are NOT on a writeShellApplication PATH, and a reap whose binary cannot be found reports 'nothing running', which is the answer that lets a second rank start over the first";
    # The reap grace is derived from the tick, not configured twice: the reap runs
    # inside a tick, so a grace longer than the convergence quantum leaves a tick
    # still reaping when the next is due.
    assert
      watcherEnv.CLUSTER_RANK_REAP_GRACE_SECS == toString watcher.StartInterval
      || throw "cluster: the SIGTERM reap grace must be derived from the watcher tick (${toString watcher.StartInterval}s), or a reap can outlive the tick that started it";
    # The ledger, and the cap that halts BEFORE exhaustion rather than after
    # errno 96. The cap is maxKickstarts by derivation — both count the same
    # resource, one domain per event — so raising one raises the other.
    assert
      watcherEnv.CLUSTER_PD_DEBT_MAX
      == toString hmConfigCluster.config.programs.mlx.clusterMode.maxKickstarts
      || throw "cluster: the PD debt cap must be derived from maxKickstarts. Both count protection domains this host is willing to lose before refusing to start a rank — a failed init leaks one, a SIGKILLed rank leaks one — so a second independent number would let one budget silently exceed the other";
    # THE CAP MUST RESERVE, NOT MERELY AVOID EXHAUSTION. The device budget is a
    # measured fact — ibv_devinfo -v reports max_pd = 11 on every RDMA device of
    # this hardware, NOT the ~60 sessions ml-explore/mlx#3207 quotes for other
    # machines. A cap of 10 would clear "below 11" and still be wrong, which is
    # why the invariant is a reserve rather than a ceiling: see
    # docs/runbooks/rdma-protection-domains.md and the maxKickstarts option for
    # the full reasoning. It holds at 5 and fails at 6, which is the point.
    assert
      watcherEnv.CLUSTER_PD_DEVICE_BUDGET
      == toString hmConfigCluster.config.programs.mlx.clusterMode.devicePdBudget
      || throw "cluster: the watcher must carry the measured device PD budget (ibv_devinfo -v max_pd). Every operator message states debt as a fraction of it, and a missing budget renders those as '? ' — a denominator nobody can act on";
    assert
      2 * hmConfigCluster.config.programs.mlx.clusterMode.maxKickstarts
      <= hmConfigCluster.config.programs.mlx.clusterMode.devicePdBudget
      || throw "cluster: the PD debt cap must RESERVE at least as many protection domains as it is willing to lose (2 * maxKickstarts <= devicePdBudget). The cap is not a distance from exhaustion: a live session allocates domains of its own, max_qp and max_cq are equally scarce, and free domains are unobservable — so a cap that walks up to the measured budget leaves the attempt that would have worked with nothing to allocate";
    assert
      builtins.match ".*/mlx-cluster/pd-debt" watcherEnv.CLUSTER_PD_DEBT_FILE != null
      || throw "cluster: the watcher must carry the PD ledger path. cluster-detach WRITES it and the watcher READS it, so it is defined once in cluster-mode.nix; two derivations of one path are a writer and a reader on different files";
    # The ledger must NOT live at the link-state path or share a name with a
    # marker the teardown clears. A link cycle, a manual clear and cluster-join
    # all reset halt state; none of them returns a protection domain.
    assert
      watcherEnv.CLUSTER_PD_DEBT_FILE != watcherEnv.CLUSTER_STATE_FILE
      || throw "cluster: the PD ledger must be its own file — anything the teardown clears would erase debt that only a reboot can actually settle";
    assert
      builtins.elem "cluster-join" cliEnvs && builtins.elem "cluster-detach" cliEnvs
      || throw "cluster: both lifecycle commands must ship — cluster-detach is the only writer of the PD ledger and cluster-join is the operator-facing gate that reads it";
    # --- the ledger's CALL SITES, not just its plumbing ------------------------
    # tests/test-pd-debt.sh proves the ledger functions behave. It cannot prove
    # anyone still CALLS them: delete the pd_debt_record line from cluster-detach
    # and all 39 of those assertions still pass while a SIGKILLed rank silently
    # stops costing anything. Same shape as "a reap that matches nothing looks
    # exactly like nothing to clean up", which is what this whole change is about.
    #
    # Live cluster formation cannot be exercised in CI — and, while the Proxmox
    # estate is down, not by hand either — so the wiring is asserted rather than
    # observed. These are the cheapest checks that fail when a call site vanishes.
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
    helpers.mkMarker "check-mlx-cluster-pd-env" "MLX RDMA protection-domain guard env contract: anchored rank pattern derived from the rank argv, absolute pgrep/kill seams, tick-derived reap grace, and a boot-scoped ledger whose maxKickstarts-derived cap reserves at least half the measured device budget verified";
}
