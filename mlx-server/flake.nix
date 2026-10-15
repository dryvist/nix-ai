{
  description = "MLX server development shell";

  inputs.nix-devenv.url = "github:dryvist/nix-devenv?ref=v0";

  outputs =
    { nix-devenv, ... }:
    let
      shell = builtins.getFlake (
        "git+https://github.com/dryvist/nix-devenv?ref=v0&rev=" + nix-devenv.rev + "&dir=shells/mlx-server"
      );
    in
    {
      inherit (shell) devShells;
    };
}
