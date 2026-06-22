# Marketplace registry for programs.claude.plugins.marketplaces.
#
# Extracted from claude-config.nix to keep that file under its file-size cap.
# All marketplace wiring lives here: it derives the package versions Renovate
# tracks, pulls the catalog + synthetic-wrapper derivations from nix-claude-code,
# overlays each catalog entry with its resolved flakeInput, and registers the
# nix-ai-local marketplaces (jacobpevans, fabric, karpathy, ponytail) that are
# not yet in nix-claude-code's catalog. Pure value — no activation/symlink
# behavior (that stays in nix-claude-code + modules/default.nix).
{
  lib,
  pkgs,
  marketplaceInputs,
  fabric-src,
  nix-claude-code,
}:
let
  # Versions come from lib/versions.nix (single source of truth for Renovate).
  # fabric/package.nix reads its version from the same file, so this avoids
  # evaluating the full fabric-ai derivation just to extract a version string.
  versions = import ../../lib/versions.nix;
  fabricVersion = versions.fabric;
  browserUseVersion = versions.browserUse;

  # Catalog defines names + source URLs; overrides build the four synthetic
  # derivations (browser-use, cribl, jacobpevans, fabric).
  inherit (nix-claude-code.lib) marketplaceCatalog;
  marketplaceOverrides = nix-claude-code.lib.marketplaceOverrides {
    inherit
      pkgs
      lib
      marketplaceInputs
      fabric-src
      fabricVersion
      browserUseVersion
      ;
  };
  inherit (marketplaceOverrides)
    browserUseMarketplace
    criblPackValidatorMarketplace
    jacobpevansMarketplace
    fabricMarketplace
    ;

  # Overlay each nix-claude-code catalog entry with the resolved flakeInput
  # (synthetic for the four wrapper derivations; raw marketplace input otherwise).
  base = lib.mapAttrs (
    name: marketplace:
    marketplace
    // {
      flakeInput = marketplaceInputs.${name} or null;
    }
  ) (marketplaceCatalog.marketplaces or marketplaceCatalog);
in
base
// {
  "browser-use-skills" = (base."browser-use-skills" or { }) // {
    flakeInput = browserUseMarketplace;
  };
  "vct-cribl-pack-validator-skills" = (base."vct-cribl-pack-validator-skills" or { }) // {
    flakeInput = criblPackValidatorMarketplace;
  };
  # jacobpevans-cc-plugins isn't in nix-claude-code's catalog yet;
  # register it directly with the synthetic wrapper derivation.
  "jacobpevans-cc-plugins" = {
    source = {
      type = "github";
      url = "JacobPEvans/claude-code-plugins";
    };
    flakeInput = jacobpevansMarketplace;
  };
  "fabric-patterns" = {
    source = {
      type = "github";
      url = "danielmiessler/fabric";
    };
    flakeInput = fabricMarketplace;
  };
  # karpathy-skills lives in nix-ai (input + tier file).
  # nix-claude-code's catalog doesn't include it.
  "karpathy-skills" = {
    source = {
      type = "github";
      url = "forrestchang/andrej-karpathy-skills";
    };
    flakeInput = marketplaceInputs.karpathy-skills;
  };
  # ponytail lives in nix-ai (input + tier file), same as karpathy-skills.
  "ponytail" = {
    source = {
      type = "github";
      url = "DietrichGebert/ponytail";
    };
    flakeInput = marketplaceInputs.ponytail;
  };
}
