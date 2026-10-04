# Selection schema for the model catalog; its key is a catalog-data.nix entry.
{ lib }:
lib.mkOption {
  type = lib.types.attrsOf (
    lib.types.submodule {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this catalog entry is compiled into the serving config.";
        };
        class = lib.mkOption {
          type = lib.types.enum [
            "resident"
            "swap"
          ];
          description = "Validated serving class: resident (preload-capable brain, big caps) or swap (on-demand, idle-unloaded, small caps). The entry must offer the class.";
        };
        roles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Logical AI-stack roles served by this catalog entry. The catalog resolves the physical model ID.";
        };
        tweaks = {
          cacheMemoryMb = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 1024 32768);
            default = null;
            description = "Override the class profile's KV-cache budget (MB), within safe bounds.";
          };
          maxNumSeqs = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 1 16);
            default = null;
            description = "Override the class profile's continuous-batch width, within safe bounds.";
          };
          maxRequestTokens = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 4096 131072);
            default = null;
            description = "Override the class profile's per-request token ceiling, within safe bounds.";
          };
          ttl = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 300 3600);
            default = null;
            description = "Swap-class only: idle seconds before unload (both llama-swap ttl and worker --auto-unload-idle-seconds).";
          };
        };
      };
    }
  );
  default = { };
  example = lib.literalExpression ''
    {
      qwen38-27b.class = "resident";
      mimo-9b.class = "resident";
      unlimited-ocr.class = "swap";
    }
  '';
  description = "Validated-model catalog selections. Keys name entries in modules/mlx/catalog-data.nix; the catalog owns parser stacks and per-class flag profiles, the host only picks entries, classes, and bounded tweaks.";
}
