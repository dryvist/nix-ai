# Each lifecycle command gets only the shell functions it calls. The files are
# concatenated in order, so dependencies appear before their callers.
{
  peerState = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-peer-state-serve.sh
  ];

  join = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-peer-state-write.sh
    ./scripts/cluster-peer-state.sh
    ./scripts/cluster-link-locate.sh
    ./scripts/cluster-link-repair.sh
    ./scripts/cluster-rank-status.sh
    ./scripts/cluster-rank-reap.sh
    ./scripts/cluster-pd-count.sh
    ./scripts/cluster-pd-gate.sh
    ./scripts/cluster-room.sh
    ./scripts/cluster-wired-limit.sh
    ./scripts/cluster-serving-restore.sh
    ./scripts/cluster-teardown.sh
    ./scripts/cluster-join.sh
  ];

  detach = [
    ./scripts/cluster-boot-scope.sh
    ./scripts/cluster-peer-state-write.sh
    ./scripts/cluster-rank-status.sh
    ./scripts/cluster-rank-reap.sh
    ./scripts/cluster-pd-count.sh
    ./scripts/cluster-wired-limit.sh
    ./scripts/cluster-serving-restore.sh
    ./scripts/cluster-teardown.sh
    ./scripts/cluster-detach.sh
  ];
}
