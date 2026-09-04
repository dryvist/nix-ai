{
  nixpkgs,
  forAllSystems,
  fabric-src,
  vct-cribl-cli,
  vct-splunk-cli,
  nixosConfigurations,
  herdr-remote-src,
  herdr-hail-src,
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

    # All systems, unlike the two linux-only entries below: hail is portable
    # node and the point of exposing it is that CI can BUILD it. A module
    # default is only ever evaluated, and an npm lockfile hash that has never
    # been fetched is one that is wrong without anything saying so.
    herdr-hail = pkgs.callPackage ../modules/herdr-hail/package.nix {
      src = herdr-hail-src;
    };
    cecli = cecliPkg;
    inherit (cecliPkg.passthru) mcp;
    inherit (vctCliPkgs) vct-cribl-cli vct-splunk-cli;
  }
  // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
    # The vztmpl tofu-proxmox downloads onto every commissioned node
    # (modules/proxmox-stack/ct_templates.tf pins its URL and sha256).
    #
    # x86_64-linux ONLY, and that is not a portability oversight: the estate's
    # nodes are amd64, and the workstation that drives the deploy is
    # aarch64-darwin with no Linux builder — it cannot build this at all. CI
    # builds it; exposing the attribute on darwin would only produce a
    # confusing failure at build time instead of a clear absence at eval time.
    #
    # Built from the `herdr` guest so the template already carries the runtime
    # closure: a guest created from it boots usable rather than needing a
    # converge before it can do anything.
    herdr-lxc-template = nixosConfigurations.herdr.config.system.build.tarball;

    # Exposed as a package, not only as a module default, for two reasons: it
    # gives CI something to actually BUILD (a module default is only ever
    # evaluated), and it is where the herdr-remote-pep723-deps check reads
    # `passthru.pep723Deps` from.
    herdr-remote-relay = pkgs.callPackage ../modules/herdr-remote/package.nix {
      src = herdr-remote-src;
    };
  }
)
