# Dev shells, extracted from flake.nix to stay under the 12KB file-size gate.
{
  nixpkgs,
  forAllSystems,
  ai-llm-prompts,
}:
forAllSystems (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
  in
  {
    default = pkgs.mkShell {
      packages = [ pkgs.uv ];
      NIX_AI_PROMPT_DIR = "${
        ai-llm-prompts.packages.${system}.applications
      }/share/ai-llm-prompts/applications";
    };
  }
)
