# Every MCP catalog server started by a package runner names an exact version,
# so an upstream release can't change what runs without a reviewed bump. The
# catalog is imported directly: it is the one place these pins are written.
{ pkgs }:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  catalog = import ../../modules/mcp/catalog.nix { inherit pkgs; };
  runners = [
    "bunx"
    "npx"
    "uvx"
  ];
  # The runner's arguments, or null when the server does not start a runner.
  # A server may start its runner through `env` (`env -u NAME uvx ...`); the
  # runner is then the first argument that names one.
  runnerArgs =
    server:
    let
      command = server.command or "";
      args = server.args or [ ];
      index = lib.lists.findFirstIndex (arg: builtins.elem arg runners) null args;
    in
    if builtins.elem command runners then
      args
    else if command == "env" && index != null then
      lib.drop (index + 1) args
    else
      null;
  # The package spec: the value after `--from` when present, otherwise the
  # first argument that is not a flag.
  specOf =
    args:
    let
      fromIndex = lib.lists.findFirstIndex (arg: arg == "--from") null args;
    in
    if fromIndex != null then
      lib.elemAt args (fromIndex + 1)
    else
      lib.findFirst (arg: !(lib.hasPrefix "-" arg)) "" args;
  # An exact version: three numeric components after `@`, after `@v` (a git
  # tag) or after `==`.
  pinned = spec: builtins.match "(@[^/@]+/)?[^@=]+(@v?|==)[0-9]+[.][0-9]+[.][0-9]+.*" spec != null;
  unpinned = lib.attrNames (
    lib.filterAttrs (
      _: server:
      let
        args = runnerArgs server;
      in
      args != null && !(pinned (specOf args))
    ) catalog
  );
in
{
  mcp-catalog-pins = helpers.mkDefaultsRegression {
    label = "MCP catalog pins";
    checkName = "check-mcp-catalog-pins";
    checks = [
      {
        name = "package-runner servers without an exact version";
        actual = unpinned;
        expected = [ ];
      }
    ];
  };
}
