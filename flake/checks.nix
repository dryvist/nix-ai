# Regression suite wiring, extracted from flake.nix to stay under the 12KB
# file-size gate. The public `nix-ai.checks.<system>` shape is unchanged.
#
# Scoped to x86_64-linux only so `nix flake check --all-systems` succeeds from
# a single linux runner. All checks in lib/checks.nix are source-only or
# evaluation-wrapped — running once on the CI system is sufficient.
# Cross-platform breakage is still caught by `--all-systems` evaluating
# `packages.<system>`, `formatter.<system>`, and `overlays.default` on every
# declared system.
{
  self,
  nixpkgs,
  home-manager,
  nixAiLib,
  ai-llm-prompts,
  herdr-remote-src,
  src,
}:
let
  system = "x86_64-linux";
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  orchestratorPromptNames = [
    "nix-ai-code-explain-example"
    "nix-ai-code-review-analysis-example"
    "nix-ai-code-review-categorization-example"
    "nix-ai-code-review-example"
    "nix-ai-default-system"
    "nix-ai-structured-extract-example"
    "nix-ai-vault-search-example"
  ];
in
{
  ${system} =
    (import (src + "/lib/checks.nix") {
      inherit
        pkgs
        home-manager
        src
        ;
      aiModule = self.homeManagerModules.default;
      inherit (nixAiLib) renderAutonomous;
    })
    // {
      # `nix flake check` only *evaluates* packages.<system> (reports "build
      # skipped") — it never compiles them, so a stale fabric vendorHash after a
      # fabric-src bump passes CI unnoticed (this happened twice: #1145, fixed by
      # #1156/#1159). Aliasing the package as a check forces the Go build — and
      # its vendorHash verification — to actually run. Scoped to the CI system
      # (x86_64-linux) like every other check so a single linux runner covers it.
      fabric-ai-build = self.packages.${system}.fabric-ai;

      # The only check that evaluates the NixOS half. Without it `nix flake
      # check` proves `nixosModules.herdr` is an attrset and nothing more,
      # which is how an unfree default (cursor-cli) shipped green through this
      # repo AND its consumer and was found by hand instead.
      #
      # Two things make it work, and both are easy to get wrong:
      #  - `nixpkgs.lib.nixosSystem` is used rather than the `pkgs` above,
      #    because that one sets allowUnfree. This must evaluate with the
      #    stock policy or it cannot catch the regression it exists for.
      #  - the unit's `path` is forced, not `ExecStart`. Forcing ExecStart
      #    alone does NOT pull in `agentPackages`, so it passes even when a
      #    default is unfree. Forcing `system.build.toplevel` also works but
      #    instantiates an entire NixOS closure, which was too much work for
      #    the CI runner to survive.
      # Forces drvPaths only: this evaluates, it never builds.
      herdr-nixos-eval =
        let
          host = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.herdr
              {
                services.herdr.enable = true;
                boot.loader.grub.enable = false;
                fileSystems."/" = {
                  device = "nodev";
                  fsType = "ext4";
                };
                system.stateVersion = "26.05";
              }
            ];
          };
          unit = host.config.systemd.services.herdr;
          # agentPackages reach the service through the unit's `path`, so
          # forcing every drvPath there is what catches an unfree default.
          # deepSeq because reading a couple of attributes of a large structure
          # proves nothing about the rest of it.
          forced = map (p: p.drvPath) (unit.path ++ host.config.environment.systemPackages);
        in
        # The content is a constant with NO store path in it. Interpolating
        # ExecStart (or a drvPath) puts a store reference in the output, which
        # the check's own build must then realise — on CI that means compiling
        # agent CLIs from source, because the substituter holding them is
        # untrusted there. deepSeq above does all the forcing; the content only
        # has to exist.
        builtins.deepSeq forced (pkgs.writeText "herdr-nixos-eval" "herdr NixOS module evaluated");
      # herdr-remote's dependency list is TRANSCRIBED into
      # modules/herdr-remote/package.nix from a PEP 723 block in upstream's
      # herdr_relay.py, because upstream ships no lockfile and is run with
      # `uv run`, which resolves from the network at start time — something a
      # guest built from a pinned flake must not do.
      #
      # A transcription with nothing checking it is the whole problem: a new
      # upstream import fails at RUNTIME on the guest with ModuleNotFoundError,
      # long after the closure was built and copied. This re-parses that block
      # from the pinned source and compares it to the list the package
      # actually installs, so the drift fails the build on the controller.
      #
      # It asserts set EQUALITY, not "every declared dep is present" — the
      # weaker form passes when upstream ADDS one, which is exactly the
      # direction that breaks.
      herdr-remote-pep723-deps =
        let
          inherit (nixpkgs) lib;
          text = builtins.readFile "${herdr-remote-src}/relay/herdr_relay.py";
          depLines = builtins.filter (l: lib.hasInfix "dependencies = [" l) (lib.splitString "\n" text);
          # A missing block means upstream restructured the header. Fail loudly
          # rather than silently comparing against an empty list, which would
          # pass only when our own list was empty too.
          # A missing block means upstream restructured the header. Fail loudly
          # rather than silently comparing against an empty list, which would
          # pass only when our own list was empty too.
          depLine =
            if depLines == [ ] then
              throw "herdr-remote: no PEP 723 `dependencies = [` line in relay/herdr_relay.py -- upstream restructured its header; re-check modules/herdr-remote/package.nix by hand."
            else
              builtins.head depLines;
          # Split on the quote character and keep the odd indices: those are
          # exactly the quoted requirement strings. Deliberately NOT a bracket
          # regex -- `[^]]` is valid POSIX but libstdc++'s ERE engine, which is
          # what builtins.match uses, rejects it outright.
          quoted = builtins.genList (i: builtins.elemAt (lib.splitString "\"" depLine) (i * 2 + 1)) (
            (builtins.length (lib.splitString "\"" depLine) - 1) / 2
          );
          # "websockets>=14.0" -> "websockets": keep the distribution name,
          # drop every PEP 440 comparator.
          nameOf =
            req:
            let
              m = builtins.match "([A-Za-z0-9_.-]+).*" req;
            in
            if m == null then null else builtins.head m;
          upstream = lib.sort (a: b: a < b) (builtins.filter (x: x != null) (map nameOf quoted));
          ours = lib.sort (a: b: a < b) self.packages.${system}.herdr-remote-relay.pep723Deps;
        in
        if upstream == ours then
          pkgs.writeText "herdr-remote-pep723-deps" "matched: ${lib.concatStringsSep " " ours}"
        else
          throw ''
            herdr-remote dependency drift.
              upstream relay/herdr_relay.py PEP 723: ${lib.concatStringsSep " " upstream}
              modules/herdr-remote/package.nix:      ${lib.concatStringsSep " " ours}
            Reconcile package.nix's pep723Deps with upstream, then re-run.
          '';

      orchestrator-prompt-assets =
        assert builtins.all (
          name: builtins.pathExists (ai-llm-prompts + "/applications/${name}.md")
        ) orchestratorPromptNames;
        pkgs.writeText "nix-ai-orchestrator-prompt-assets" ''
          Validated ${toString (builtins.length orchestratorPromptNames)} catalog prompts.
        '';
    };
}
