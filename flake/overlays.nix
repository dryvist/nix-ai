# Default overlay — injects every flake-exported package into pkgs.
#
# Consumers register this via:
#   nixpkgs.overlays = [ nix-ai.overlays.default ];
# Required when importing this flake's homeManagerModules, since those modules
# reference pkgs.<name> (e.g. modules/cecli/packages.nix uses pkgs.cecli). Any
# package added to `packages` is automatically available — consumers do not
# need to enumerate package names.
{ self }:
{
  # Use prev.stdenv.hostPlatform.system (not prev.system). The bare `system`
  # attribute is a deprecated alias in nixpkgs whose warnAlias machinery
  # triggers infinite recursion when evaluated inside an overlay during
  # home-manager's _module.args.pkgs path. The stdenv check guards against the
  # empty attrsets the flake schema validator passes (`overlay {} {}`).
  default =
    _final: prev:
    if prev ? stdenv then self.packages.${prev.stdenv.hostPlatform.system} or { } else { };
}
