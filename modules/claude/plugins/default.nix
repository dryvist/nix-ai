# Claude Code Plugin Tier Enablement (nix-ai user choices)
#
# The marketplace catalog and synthetic-marketplace derivations now live in
# nix-claude-code (see lib.marketplaceCatalog and lib.marketplaceOverrides
# in that flake). This file aggregates the per-user enablement decisions —
# which plugin@marketplace pairs are turned on — across five tier files.
#
# Tier 1 — Anthropic Official
# Tier 2 — First-party AI/cloud vendors
# Tier 3 — Personal (jacobpevans-cc-plugins, auto-discovered)
# Tier 4 — Community by GitHub-stars popularity
# Tier 5 — Niche / specialty
#
# Each tier file exports `enabledPlugins`. All attrsets are merged below;
# keys contain their `@marketplace` suffix so collisions across files
# surface at evaluation time.
{
  lib,
  marketplaceInputs,
  ...
}:

let
  # 03-personal.nix discovers plugins by walking jacobpevans-cc-plugins/.
  inherit (marketplaceInputs) jacobpevans-cc-plugins;

  official = import ./01-official.nix { };
  vendors = import ./02-vendors.nix { };
  personal = import ./03-personal.nix { inherit lib jacobpevans-cc-plugins; };
  community = import ./04-community.nix { };
  specialty = import ./05-specialty.nix { };

  enabledPlugins =
    official.enabledPlugins
    // vendors.enabledPlugins
    // personal.enabledPlugins
    // community.enabledPlugins
    // specialty.enabledPlugins;
in
{
  inherit enabledPlugins;
}
