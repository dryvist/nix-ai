# Whole-guest NixOS configurations for the herdr estate.
#
# WHY THIS EXISTS. nixosModules.herdr is a module — importable, but not
# deployable on its own. ansible-proxmox-ai's `nixos_deploy` role runs
# `nixos-rebuild --flake github:dryvist/nix-ai#<host> --target-host ...`, and
# that dereferences `nixosConfigurations.<host>`. Without this file the flake
# exports the module and nothing can deploy it, which is the state the herdr
# work was in: a module with no consumer and a role with no attribute.
#
# WHY x86_64-linux ONLY. These are Proxmox LXC guests on amd64 nodes. There is
# no aarch64 node in the estate, and the workstation that orchestrates the
# deploy is aarch64-darwin — it evaluates these fine but cannot BUILD them, so
# the closure is built on the target or in CI. Same scoping as flake/checks.nix.
#
# WHY proxmox-lxc.nix RATHER THAN nixos-generators. nixpkgs ships the profile
# itself (nixos/modules/virtualisation/proxmox-lxc.nix) and it produces
# `config.system.build.tarball`, which is exactly the vztmpl Proxmox wants.
# nixos-generators was deprecated in NixOS 25.05 and archived; depending on it
# would add an input to replace something nixpkgs already does.
{
  nixpkgs,
  llm-agents,
  nixosModules,
}:

let
  system = "x86_64-linux";

  # Shared by every herdr guest. Kept minimal on purpose: everything that makes
  # a guest DIFFERENT belongs in that guest's own module below, and everything
  # the estate does uniformly (users, DNS, time) is Ansible's job, not this
  # flake's. The rule this repo holds to is that nix owns the software and
  # Ansible owns the orchestration.
  base =
    { lib, modulesPath, ... }:
    {
      imports = [ "${modulesPath}/virtualisation/proxmox-lxc.nix" ];

      # An unprivileged LXC has no say over its own network, clock or kernel;
      # Proxmox supplies all three. Declaring them here would produce units
      # that fail on every boot for structural reasons.
      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };

      # NOT set here: networking.useDHCP and networking.hostName. With
      # manageNetwork/manageHostName false, proxmox-lxc.nix pins useDHCP to
      # false and hostName to `mkForce ""` so the hypervisor owns both — which
      # is why every guest's system derivation is named `...-unnamed-lxc-...`
      # and why the estate's hostname lives in deployment.json, not here.
      # Declaring either would be dead config that reads as intent.

      # The guest is reached over SSH — both by `nixos-rebuild --target-host`
      # pushing a closure and by `herdr --remote` shelling out. Passwords are
      # off: the estate authenticates with certificates minted from the OpenBao
      # SSH CA, and a password path would be a second, weaker way in.
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
      };

      # nixos-rebuild --target-host copies a closure and activates it as root.
      users.users.root.openssh.authorizedKeys.keys = lib.mkDefault [ ];

      # Flakes, because the deploy IS a flake reference. A guest that cannot
      # evaluate a flake cannot be re-converged from itself if the controller
      # is ever unavailable.
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Pinned to the release these guests are first built against. Never
      # advance this to "follow latest" — it is a compatibility declaration,
      # not a version, and moving it silently migrates state formats.
      system.stateVersion = "26.05";
    };

  mkGuest =
    { modules }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      # hostName is the ATTRIBUTE name, not networking.hostName (forced empty
      # above). `nixos-rebuild --flake ...#<hostName>` is what selects a guest,
      # and ansible's nixos_deploy defaults that attribute to the inventory
      # hostname — so these keys must match the guest hostnames in
      # deployment.json exactly.
      modules = [ base ] ++ modules;
      specialArgs = { inherit llm-agents; };
    };
in
{
  # The runtime. Owns the terminals every coding agent runs in, and the only
  # guest whose state (/var/lib/herdr — agent credentials, worktrees, session
  # state) does not rebuild from the flake.
  herdr = mkGuest {
    modules = [
      nixosModules.herdr
      {
        services.herdr = {
          enable = true;
          # Ansible writes this at 0600 out of band; the unit loads it with a
          # leading `-`, so a first converge starts inert rather than failing.
          environmentFile = "/var/lib/herdr/.env";
        };
      }
    ];
  };

  # The web and phone dashboard. Drives the runtime over SSH via HERDR_REMOTES,
  # so it holds no agent state of its own and is disposable by design.
  herdr-ui = mkGuest {
    modules = [
      nixosModules.herdr-remote
      {
        services.herdr-remote = {
          enable = true;
          environmentFile = "/var/lib/herdr-remote/.env";
        };
      }
    ];
  };
}
