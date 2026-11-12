# herdr-hail repeat dedupe: the patch is applied by the package build, and the
# RepeatGuard it adds latches one notification per status stay, keyed by
# terminal id and status only — never by pane content, which keeps changing
# while the agent waits.
{ pkgs }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;

  packageSource = builtins.readFile ../../modules/herdr-hail/package.nix;
  patchSource = builtins.readFile ../../modules/herdr-hail/repeat-dedupe.patch;
in
{
  herdr-hail-repeat-dedupe =
    assert lib.assertMsg (lib.hasInfix "./repeat-dedupe.patch" packageSource)
      "herdr-hail package.nix does not apply repeat-dedupe.patch";
    assert lib.assertMsg (lib.hasInfix "class RepeatGuard" patchSource)
      "repeat-dedupe.patch does not add the RepeatGuard in-state latch";
    assert lib.assertMsg (lib.hasInfix "mayNotify" patchSource)
      "repeat-dedupe.patch does not gate notifications through RepeatGuard.mayNotify";
    assert lib.assertMsg (lib.hasInfix "ten reports of the same blocked state notify exactly once" patchSource)
      "repeat-dedupe.patch does not carry the ten-tick repeat regression test";
    assert lib.assertMsg (!(lib.hasInfix "notification.context].join" patchSource))
      "repeat-dedupe.patch still keys repeats on pane content, which changes while the agent waits";
    helpers.mkMarker "check-herdr-hail-repeat-dedupe" "herdr-hail notifies once per status stay via the RepeatGuard latch.";
}