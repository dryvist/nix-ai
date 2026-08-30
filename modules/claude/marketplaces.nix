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
  # Claude owns this marketplace's content; Nix only declares it.
  #
  # Deliberately no flakeInput. A flakeInput makes nix-claude-code symlink
  # ~/.claude/plugins/marketplaces/<name> at a read-only /nix/store path, which
  # Claude can neither git-pull into nor stamp an mtime on (it reports
  # lastUpdated 1970-01-01), so every store-path change purged the plugin cache
  # with no working path back. Leaving it null lets Claude clone and self-heal
  # the directory itself, which is what the other marketplaces already do.
  #
  # This does not affect the shared ~/.agents skills tree: agent-skills
  # discovery walks marketplaceInputs directly, not this flakeInput, so
  # OpenCode/Gemini keep the same store paths as before.
  #
  # Registration survives via settings.nix extraKnownMarketplaces, which maps
  # every declared marketplace regardless of flakeInput.
  "jacobpevans-cc-plugins" = {
    source = {
      type = "github";
      url = "JacobPEvans/claude-code-plugins";
    };
  };
  # Inherit the catalog source (nix-claude-code marks fabric-patterns
  # source.type = "local" → a Claude `directory` source, so Claude reads the
  # synthetic marketplace in place instead of re-cloning raw upstream and
  # clobbering it). Only override flakeInput, matching browser-use/cribl above.
  "fabric-patterns" = (base."fabric-patterns" or { }) // {
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
  # autoresearch lives in nix-ai (input + tier entry), same as ponytail.
  # Ships a native .claude-plugin/marketplace.json; content is pinned via the
  # flake input — the GitHub source here is registry identity metadata only.
  "autoresearch" = {
    source = {
      type = "github";
      url = "uditgoenka/autoresearch";
    };
    flakeInput = marketplaceInputs.autoresearch;
  };
  # context-engineering-kit lives in nix-ai (input + tier entry). Ships a
  # native .claude-plugin/marketplace.json; only the `kaizen` plugin is
  # enabled, and it carries both the `kaizen` and `why` skills.
  "context-engineering-kit" = {
    source = {
      type = "github";
      url = "NeoLabHQ/context-engineering-kit";
    };
    flakeInput = marketplaceInputs.context-engineering-kit;
  };
  # managing-dependencies is a single-plugin marketplace rooted at ./.
  "managing-dependencies" = {
    source = {
      type = "github";
      url = "andrew/managing-dependencies";
    };
    flakeInput = marketplaceInputs.managing-dependencies;
  };
  # langfuse-skills is a single-plugin marketplace rooted at ./.
  "langfuse-skills" = {
    source = {
      type = "github";
      url = "langfuse/skills";
    };
    flakeInput = marketplaceInputs.langfuse-skills;
  };
}
