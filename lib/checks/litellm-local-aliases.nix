# Router capability alias consistency — pure, no network.
#
# programs.litellmLocal.aliases is the shared alias contract every consumer
# renders from. This proves the routed clients that render from it
# (OpenCode's provider.litellm + agent tiers, Codex's per-alias profile
# files) still match it exactly — asserted both ways, so a consumer silently
# reintroducing an inline model name outside the list fails the build just as
# a consumer silently dropping an alias would.
#
# What this canNOT prove: that the router actually serves every alias here.
# That needs a live HTTP call, which a pure eval cannot make — see
# lib/checks/scripts/litellm-alias-subset-check.sh for the CI-time
# counterpart, which skips cleanly when no router credentials are in the
# environment rather than silently passing.
{
  pkgs,
  hmConfig,
  homelab-contracts,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs;
  aliases = cfg.litellmLocal.aliases;
  laneVocabulary = (import ../lanes.nix { src = homelab-contracts; }).vocabulary;

  mismatch =
    name: actual:
    let
      unexpected = builtins.filter (n: !(builtins.elem n aliases)) actual;
      missing = builtins.filter (n: !(builtins.elem n actual)) aliases;
    in
    {
      inherit name unexpected missing;
      ok = unexpected == [ ] && missing == [ ];
    };

  results = [
    (mismatch "opencode.litellmRoles" cfg.opencode.litellmRoles)
    (mismatch "codex.litellmProfileNames" cfg.codex.litellmProfileNames)
  ];
  failures = builtins.filter (r: !r.ok) results;

  unknownAliases = builtins.filter (n: !(builtins.elem n laneVocabulary)) aliases;
in
{
  litellm-alias-list-consistency =
    assert
      failures == [ ]
      || throw "consumer(s) drifted from programs.litellmLocal.aliases: ${builtins.toJSON failures}. Every routed consumer must render from that option.";
    helpers.mkMarker "check-litellm-alias-list-consistency" "OpenCode and Codex both render exactly programs.litellmLocal.aliases, in both directions";

  litellm-alias-lane-vocabulary =
    assert
      unknownAliases == [ ]
      || throw "programs.litellmLocal.aliases names outside the homelab-contracts lane vocabulary: ${builtins.toJSON unknownAliases}.";
    helpers.mkMarker "check-litellm-alias-lane-vocabulary" "every configured router alias is in the homelab-contracts lane vocabulary";
}
