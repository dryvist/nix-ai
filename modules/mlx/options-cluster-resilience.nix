# The per-cluster interpreter override used by lifecycle commands.
{ lib, ... }:
{
  options.programs.mlx.clusterMode.appleInterpreter = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      Per-cluster override for programs.mlx.appleInterpreter. null (the
      default) inherits the module-wide value, which is where the convention
      and its rationale live — see ./options-launch.nix.

      Present only so a single host can opt one cluster agent out without
      changing the estate default. Almost nothing should set this.
    '';
  };
}
