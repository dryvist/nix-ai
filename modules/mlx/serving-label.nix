# The launchd label family of the standalone model servers: the unsuffixed
# default agent and one `dev.mlx-model-server.<name>` agent per extra resident.
# The watchdog shares the prefix, so it is a serving agent too: the join stops it
# with the servers and the restore brings it back.
#
# The single definition of that predicate. Module code and the static checks both
# import it, so they cannot disagree about which agents count as serving.
{ lib }:
{
  isServingLabel =
    label: label == "dev.mlx-model-server" || lib.hasPrefix "dev.mlx-model-server." label;
}
