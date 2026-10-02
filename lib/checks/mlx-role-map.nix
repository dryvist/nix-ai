# Role map contract (modules/mlx/role-map-errors.nix) against the catalog.
#
# Three rules, each with a positive case (the pinned homelab-contracts map
# passes) and a negative case (a map breaking only that rule is reported):
#   - every map model key is a catalog entry with the same physical id
#   - a dense model has concurrency 1
#   - every model a host class keeps, and every role it resolves, is declared
{ pkgs, roleMap }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  catalog = import ../../modules/mlx/catalog-data.nix;
  errorsFor =
    candidate:
    import ../../modules/mlx/role-map-errors.nix {
      inherit catalog;
      roleMap = candidate;
    };

  realErrors = errorsFor roleMap;

  unknownModel = roleMap // {
    models = roleMap.models // {
      not-in-catalog = {
        id = "mlx-community/not-in-catalog";
        concurrency = 1;
      };
    };
  };
  denseParallel = roleMap // {
    models = roleMap.models // {
      qwen38-27b = roleMap.models.qwen38-27b // {
        dense = true;
        concurrency = 2;
      };
    };
  };
  undeclaredHostModel = roleMap // {
    hosts = roleMap.hosts // {
      server = roleMap.hosts.server // {
        swap = roleMap.hosts.server.swap ++ [ "undeclared-model" ];
      };
    };
  };

  reports = bad: pattern: builtins.any (e: builtins.match pattern e != null) (errorsFor bad);
in
{
  mlx-role-map =
    assert
      realErrors == [ ]
      || throw "role map: the pinned homelab-contracts map breaks the catalog contract: ${builtins.toJSON realErrors}";
    assert
      reports unknownModel ".*not-in-catalog.*not a catalog entry.*"
      || throw "role map: a model key absent from the catalog must be reported";
    assert
      reports denseParallel ".*dense model `qwen38-27b` must have concurrency 1.*"
      || throw "role map: a dense model with concurrency 2 must be reported";
    assert
      reports undeclaredHostModel ".*host class `server` keeps undeclared model `undeclared-model`.*"
      || throw "role map: a host class keeping an undeclared model must be reported";
    helpers.mkMarker "check-mlx-role-map" "role map: catalog keys, dense concurrency and host-class models hold; each rule's negative case is reported";
}
