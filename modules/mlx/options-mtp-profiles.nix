{ lib, ... }:
{
  options.programs.mlx.modelMtpProfiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "experimental multi-token prediction for this model";
          drafterModel = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Physical model id or local path for the speculative drafter. Required when MTP is enabled.";
          };
          maxKvTokens = lib.mkOption {
            type = lib.types.ints.between 32768 262144;
            default = 131072;
            description = "Maximum token window passed to the native mlx-vlm server for this MTP target.";
          };
          maxNumSeqs = lib.mkOption {
            type = lib.types.ints.between 1 4;
            default = 1;
            description = "Native mlx-vlm continuous-batch width. It must equal the proxy concurrency limit for this target.";
          };
          tokenQueueTimeoutSeconds = lib.mkOption {
            type = lib.types.ints.between 60 3600;
            default = 1800;
            description = "Native mlx-vlm token-queue timeout for long-context MTP requests.";
          };
          draftBlockSize = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 2 8);
            default = null;
            description = "Optional native mlx-vlm MTP draft block size. Values below 2 are rejected because a one-token run is not a speculative-decoding measurement.";
          };
        };
      }
    );
    default = { };
    description = "Opt-in experimental MTP profiles. An enabled profile requires the native mlx-vlm backend, a drafter, and matched proxy/worker concurrency; it never changes a model's default profile.";
  };
}
