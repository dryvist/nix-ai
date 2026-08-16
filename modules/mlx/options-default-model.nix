# Which catalog entry holds the "default" role, and the runtime override for it.
#
# Two hosts share one serving configuration and differ only in this key, so it
# is a declared input rather than a per-host `catalog.<key>.roles = [ "default" ]`
# line. It names a CATALOG KEY, never a physical HF id: a consumer pinned to a
# physical id loses its backend the moment the catalog swaps weights.
#
# The override path (mlx-default-model, ./default-model.py) re-points the
# "default" alias in the MUTABLE runtime config with no rebuild. The keymap
# below is what lets that script stay key-based: it is the only place the
# key -> physical mapping crosses from Nix into the runtime.
#
# Split from options-catalog.nix for the per-file size gate.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mlx;
  catalogData = import ./catalog-data.nix;
  key = cfg.defaultModelKey;
  selection = cfg.catalog.${key} or null;
  entry = catalogData.${key} or null;
  # Entries whose own `roles` list already claims "default".
  claimants = lib.attrNames (
    lib.filterAttrs (_: sel: sel.enable && lib.elem "default" sel.roles) cfg.catalog
  );
  enabledKeys = lib.filterAttrs (name: sel: sel.enable && catalogData ? ${name}) cfg.catalog;
in
{
  options.programs.mlx = {
    defaultModelKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "qwen38-27b";
      description = ''
        Catalog key (modules/mlx/catalog-data.nix) that receives the "default"
        AI-stack role. The entry must be enabled in programs.mlx.catalog. Swap
        class is permitted — a swap-class entry may own "default" and still be
        registry-backed. Runtime override without a rebuild: mlx-default-model.
      '';
    };

    # Split attrset/file so regression checks can assert the mapping purely —
    # reading the derivation back would need it BUILT, which on a Mac means the
    # x86_64-linux check silently cannot evaluate at all.
    defaultModelKeymap = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      internal = true;
      readOnly = true;
      default = {
        declared = key;
        keys = lib.mapAttrs (name: _: catalogData.${name}.model) enabledKeys;
      };
      defaultText = lib.literalMD "declared key plus every enabled catalog key";
      description = "Catalog-key -> physical-id map handed to mlx-default-model.";
    };

    defaultModelKeymapFile = lib.mkOption {
      type = lib.types.path;
      internal = true;
      readOnly = true;
      default = pkgs.writeText "mlx-default-model-keymap.json" (builtins.toJSON cfg.defaultModelKeymap);
      defaultText = lib.literalMD "`defaultModelKeymap` rendered to JSON";
      description = "Nix-generated keymap file read by mlx-default-model.";
    };

    defaultModelOverridePath = lib.mkOption {
      type = lib.types.str;
      internal = true;
      readOnly = true;
      default = "${config.home.homeDirectory}/.config/mlx/default-model.override";
      defaultText = lib.literalMD "`~/.config/mlx/default-model.override`";
      description = "Mutable file naming the catalog key that overrides the declared default.";
    };
  };

  config = lib.mkIf (cfg.enable && key != null) {
    assertions = [
      {
        assertion = entry != null;
        message = ''
          programs.mlx.defaultModelKey = "${key}" is not a catalog entry.
          Known entries: ${lib.concatStringsSep ", " (lib.attrNames catalogData)}
        '';
      }
      {
        assertion = selection != null && selection.enable;
        message = ''
          programs.mlx.defaultModelKey = "${key}" names a catalog entry that is
          not enabled in programs.mlx.catalog. The "default" role would resolve
          to a model with no llama-swap backend. Enable the entry or pick
          another key.
        '';
      }
      {
        # Two sources both claiming "default" would resolve by attrset merge
        # order — a silent winner is the defect class this option exists to
        # remove, so make the conflict fail instead.
        assertion = claimants == [ ] || claimants == [ key ];
        message = ''
          programs.mlx.defaultModelKey = "${key}" conflicts with catalog
          entr(y/ies) declaring roles = [ ... "default" ... ]:
          ${lib.concatStringsSep ", " claimants}. Declare the default role one
          way only — via defaultModelKey, or via a single entry's roles list.
        '';
      }
    ];

    services.aiStack.roleOverrides = lib.mkIf (entry != null) {
      default = lib.mkDefault entry.model;
    };
  };
}
