# Resident judge model — a small always-on worker in its OWN llama-swap
# group, separate from the mlx-models registry group. The topology compiler
# (llama-swap-topology.nix) only models a two-bucket resident/swap shape, so
# a third independent group is merged directly into llamaSwapConfigAttrs in
# default.nix rather than routed through that compiler or through
# programs.mlx.maxResidentWorkers (which would fold the judge into the same
# exclusive group as the main resident, making them evict each other).
{ lib, ... }:
{
  options.programs.mlx.judge = {
    enable = lib.mkEnableOption "a small always-resident judge model in its own llama-swap group";

    model = lib.mkOption {
      type = lib.types.str;
      description = ''
        Physical HF model id to serve as the judge. Must be pre-cached under
        HF_HOME — HF_HUB_OFFLINE=1 means an uncached id 502s rather than
        downloading.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra args appended to the judge worker's launch command.";
    };

    aliases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "judge" ];
      description = "llama-swap role aliases routed to the judge model.";
    };
  };
}
