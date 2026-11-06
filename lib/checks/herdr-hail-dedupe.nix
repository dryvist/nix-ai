# herdr-hail repeat dedupe: the patch is applied by the package build, and the
# code it adds carries the 15-minute window.
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
    assert lib.assertMsg (lib.hasInfix "REPEAT_WINDOW_MS = 15 * 60 * 1000;" patchSource)
      "repeat-dedupe.patch does not define the 15-minute repeat window";
    helpers.mkMarker "check-herdr-hail-repeat-dedupe" "herdr-hail applies repeat-dedupe.patch with a 15-minute window.";
}
