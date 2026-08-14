# VisiCore operator CLIs, built from their upstream `main` checkouts.
#
# Every field (name, version, entry point, runtime deps, build backend) is read
# out of each repo's own pyproject.toml. A flake.lock bump that moves `main`
# forward therefore carries upstream metadata changes with it, instead of
# building against a copy pinned here that silently goes stale.
{
  pkgs,
  vct-cribl-cli,
  vct-splunk-cli,
}:

let
  inherit (pkgs) lib python3Packages;

  # "click>=8.1" -> python3Packages.click. A dependency whose PyPI name is not
  # a nixpkgs attr fails evaluation loudly rather than dropping out of the build.
  pyPkg = spec: python3Packages.${lib.head (builtins.match "([A-Za-z0-9._-]+).*" spec)};

  mkCli =
    src:
    let
      toml = builtins.fromTOML (builtins.readFile (src + "/pyproject.toml"));
      inherit (toml) project;
    in
    python3Packages.buildPythonApplication {
      inherit src;
      pname = project.name;
      # hatchling projects set `dynamic = ["version"]` and point at a file.
      version = project.version or (lib.fileContents (src + "/${toml.tool.hatch.version.path}"));

      pyproject = true;
      build-system = map pyPkg toml.build-system.requires;
      dependencies = map pyPkg project.dependencies;

      # Upstream dev extras (pytest, responses, pyright) are not needed to ship
      # the CLI; pythonImportsCheck plus the --help check in lib/checks/vct-cli.nix
      # cover that the console script actually works.
      doCheck = false;
      # "cribl_cli.__main__:main" -> cribl_cli
      pythonImportsCheck = map (entry: lib.head (lib.splitString "." entry)) (
        lib.attrValues project.scripts
      );

      meta = {
        inherit (project) description;
        mainProgram = lib.head (lib.attrNames project.scripts);
      };
    };
in
{
  vct-cribl-cli = mkCli vct-cribl-cli;
  vct-splunk-cli = mkCli vct-splunk-cli;
}
