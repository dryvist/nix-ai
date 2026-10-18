# The free-memory budget checked by cluster-join at J5.
{ lib, ... }:
{
  options.programs.mlx.clusterMode.shardMemoryMb = lib.mkOption {
    type = lib.types.int;
    default = 0;
    description = ''
      Expected per-rank working set (MB) once the cluster shard is loaded.
      At J5, cluster-join requires vm_stat free, inactive, and speculative
      pages to report at least this much available memory. J1 first verifies
      that no rank process is alive. Unowned wired memory is reported for the
      operator; the kernel PD count is checked separately at J1 and J9.

      This is the free-memory budget only. GPU wired headroom is checked
      separately using compositorReserveMb. Zero disables this memory check.
      There is no safe universal default, so set it to the deployed model's
      expected per-rank working set.
    '';
  };
}
