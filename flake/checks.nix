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
      orchestrator-prompt-assets =
        assert builtins.all (
          name: builtins.pathExists (ai-llm-prompts + "/applications/${name}.md")
        ) orchestratorPromptNames;
        pkgs.writeText "nix-ai-orchestrator-prompt-assets" ''
          Validated ${toString (builtins.length orchestratorPromptNames)} catalog prompts.
        '';
    };
}
