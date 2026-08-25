{ lib, ... }:
{
  options.programs.mlx.modelMtpProfiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "experimental multi-token prediction for this model";
          draftBlockSize = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 2 8);
            default = null;
            description = "Optional vllm-mlx MTP draft block size. Values below 2 are rejected because a one-token run is not a speculative-decoding measurement.";
          };
        };
      }
    );
    default = { };
    description = "Opt-in experimental MTP profiles. An enabled profile requires the vllm-mlx backend and a serialized model concurrency limit; it never changes a model's default profile.";
  };
}
