# Router capability alias consistency — pure, no network.
#
# modules/litellm-local/aliases.nix is the ONE committed alias contract every
# consumer renders from. This proves the two consumers that render from it
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
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  aliases = import ../../modules/litellm-local/aliases.nix;
  cfg = hmConfig.config.programs;

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
in
{
  litellm-alias-list-consistency =
    assert
      failures == [ ]
      || throw "consumer(s) drifted from modules/litellm-local/aliases.nix: ${builtins.toJSON failures}. A consumer must render from that ONE list, never an inline name — add the alias there first, or remove the stray inline name.";
    helpers.mkMarker "check-litellm-alias-list-consistency" "OpenCode and Codex both render exactly the modules/litellm-local/aliases.nix contract, in both directions";
}
