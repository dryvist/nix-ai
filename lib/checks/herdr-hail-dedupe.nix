# herdr-hail repeat dedupe: the patch is applied by the package build, and the
# RepeatGuard it adds latches one notification per status stay, keyed by
# terminal id and status only. The herdr-hail-build check runs its package tests.
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
    assert lib.assertMsg (lib.hasInfix "notifyOnce" patchSource)
      "repeat-dedupe.patch does not latch only after successful delivery";
    assert lib.assertMsg (lib.hasInfix "MAX_NOTIFIED_TERMINALS = 1024" patchSource)
      "repeat-dedupe.patch does not bound notified terminal entries";
    assert lib.assertMsg
      (lib.hasInfix "ten reports of the same blocked state with changing context notify exactly once" patchSource)
      "repeat-dedupe.patch does not carry the changing-context repeat regression test";
    assert lib.assertMsg
      (lib.hasInfix "leaving blocked and re-entering notifies a second time" patchSource)
      "repeat-dedupe.patch does not carry the episode reset regression test";
    assert lib.assertMsg
      (lib.hasInfix "failed delivery leaves the blocked episode eligible for retry" patchSource)
      "repeat-dedupe.patch does not carry the failed-delivery regression test";
    assert lib.assertMsg (
      !(lib.hasInfix "notification.context].join" patchSource)
    ) "repeat-dedupe.patch still keys repeats on pane content, which changes while the agent waits";
    helpers.mkMarker "check-herdr-hail-repeat-dedupe" "herdr-hail notifies once per status stay via the RepeatGuard latch.";
}
