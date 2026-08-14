{
  nixpkgs,
  forAllSystems,
  fabric-src,
  vct-cribl-cli,
  vct-splunk-cli,
}:

forAllSystems (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    cecliPkg = pkgs.callPackage ../modules/cecli/package.nix { };
    vctCliPkgs = import ../modules/vct-cli/packages.nix {
      inherit
        pkgs
        vct-cribl-cli
        vct-splunk-cli
        ;
    };
  in
  {
    fabric-ai = pkgs.callPackage ../modules/fabric/package.nix { inherit fabric-src; };
    cecli = cecliPkg;
    inherit (cecliPkg.passthru) mcp;
    inherit (vctCliPkgs) vct-cribl-cli vct-splunk-cli;
  }
)
