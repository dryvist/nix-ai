# Cluster observation traps

Use these checks with the manual [cluster lifecycle](cluster-lifecycle.md). The lifecycle log records the gate and measured result; a single interface flag or state file does not establish the state of the whole cluster.

- **`RUNNING` is not carrier.** An admin-up interface can show `RUNNING` with no cable attached. Read `status: active` or `status: inactive` on the individual Thunderbolt interface; the bridge status does not report per-port carrier.
- **A missing link address does not identify the cable state.** It can occur while a cable is seated and the port reports active. `cluster-join` checks the address and refuses with `link-prep-not-ready`; it does not repair the interface. Run `sudo /nix/var/nix/profiles/system/activate`, then retry the join.
- **An empty Thunderbolt Bridge is expected.** The cluster link address belongs on the selected Thunderbolt interface. If it is absent or assigned to the bridge, run system activation and repeat the read-only join check; do not add bridge members by hand.
- **Local Network Privacy errors differ from link-preparation failures.** `errno 65` (`EHOSTUNREACH`) can indicate a process is blocked from local-network access; `errno 61` (`ECONNREFUSED`) means the connection reached a host with no listener. Compare the lifecycle log with a read-only `/usr/bin/curl` probe from the same user before changing link configuration.
- **A state file is not a process probe.** `link-state` and `peer-state.json` describe the last published lifecycle state. Use the `cluster-detach` rank summary and the kernel PD count to verify teardown; do not infer rank absence from `down`, a missing marker, or a launchd listing alone.
- **Read the earliest failure in a join log.** A later peer timeout or formation refusal can follow an earlier gate failure. Start with the first `REFUSE` or `FAIL` line in `~/Library/Logs/mlx-cluster/cluster-lifecycle.log` and resolve that reason before retrying.
- **`errno 60` does not identify which node needs attention.** `cluster-join` requires a fresh peer arm and matching software and model revisions before it starts a rank. Use the logged peer-state reason to check the responder, configuration, revision, or clock; there is no timed peer-readiness option to adjust.
- **A rank exit status is not a PD count.** `launchctl list`'s second column is the last exit status. Check current process state and run `ioclasscount AppleThunderboltRDMAProtectionDomain` separately before concluding whether the rank released its kernel resources.
- **Exit 3 requests an operator reboot.** No join or detach path reboots a node automatically. Reboot the Mac identified by the lifecycle log before retrying, then let J1 read the current kernel count again.

For the gate sequence and refusal actions, see [cluster-lifecycle.md](cluster-lifecycle.md). For the PD arithmetic, see [rdma-protection-domains.md](rdma-protection-domains.md).
