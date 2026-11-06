{
  pkgs,
  homelab-contracts,
  roleMap,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  src = ./fixtures/model-policy;
  policy = builtins.fromJSON (
    builtins.readFile (src + "/ansible/roles/llm_model_catalog/files/model-policy.json")
  );
  model = builtins.head policy.models;
  models = {
    example.id = model.id;
  };
  catalog.example.model = model.id;
  validate =
    args:
    import ../model-policy.nix (
      {
        inherit src;
        roleMap = { inherit models; };
        mlxCatalog = catalog;
      }
      // args
    );
  errors = candidate: validate { policy = candidate; };
  withModel = changes: policy // { models = [ (model // changes) ]; };
  accepted = candidate: errors candidate == [ ];
  fails = args: !(builtins.tryEval (builtins.deepSeq (validate args) true)).success;
  cases = {
    reads-contracts-path = validate { } == [ ];
    reads-contracts-string = validate { src = toString src; } == [ ];
    reads-contracts-input = validate { src.outPath = toString src; } == [ ];
    age-365-inclusive = accepted policy;
    age-366-rejected =
      !accepted (withModel {
        upstream_created = "2025-11-05";
      });
    future-rejected =
      !accepted (withModel {
        upstream_created = "2026-11-07";
      });
    today-accepted = accepted (withModel {
      upstream_created = policy.as_of;
    });
    quantization-keeps-upstream-age =
      !accepted (withModel {
        upstream_created = "2020-01-01";
      });
    unknown-role-model =
      validate {
        roleMap.models.unknown.id = "example/unknown";
        mlxCatalog = { };
      } != [ ];
    unknown-catalog-model =
      validate {
        roleMap.models = { };
        mlxCatalog.unknown.model = "example/unknown";
      } != [ ];
    denied-even-if-listed =
      !accepted (
        policy
        // {
          deny = [
            {
              inherit (model) id;
              reason = "fixture";
            }
          ];
        }
      );
    denied-upstream =
      !accepted (
        policy
        // {
          deny = [
            {
              id = model.upstream_id;
              reason = "fixture";
            }
          ];
        }
      );
    missing-record = !accepted (policy // { models = [ ]; });
    duplicate-record =
      !accepted (
        policy
        // {
          models = [
            model
            model
          ];
        }
      );
    ambiguous-upstream =
      !accepted (
        policy
        // {
          models = [
            model
            (
              model
              // {
                id = "example/other-copy";
                upstream_created = "2025-11-07";
              }
            )
          ];
        }
      );
    missing-upstream =
      !accepted (withModel {
        upstream_id = null;
      });
    missing-dossier =
      !accepted (withModel {
        dossier = null;
      });
    empty-dossier =
      !accepted (withModel {
        dossier = " ";
      });
    missing-date = fails { policy = withModel { upstream_created = null; }; };
    undated = fails { policy = withModel { upstream_created = ""; }; };
    malformed-date = fails { policy = withModel { upstream_created = "2026-2-01"; }; };
    impossible-date = fails { policy = withModel { upstream_created = "2026-02-30"; }; };
    invalid-month = fails { policy = withModel { upstream_created = "2026-13-01"; }; };
    invalid-as-of = fails {
      policy = policy // {
        as_of = "unknown";
      };
    };
    version = fails {
      policy = policy // {
        version = 2;
      };
    };
    negative-age-limit = fails {
      policy = policy // {
        max_age_days = -1;
      };
    };
    null-policy-rejected = fails { policy = null; };
    leap-day-365 = accepted (
      (withModel { upstream_created = "2024-02-29"; }) // { as_of = "2025-02-28"; }
    );
    leap-day-366 =
      !accepted ((withModel { upstream_created = "2024-02-29"; }) // { as_of = "2025-03-01"; });
    non-leap-century = fails { policy = withModel { upstream_created = "1900-02-29"; }; };
    leap-century = accepted (
      (withModel { upstream_created = "2000-02-29"; }) // { as_of = "2001-02-28"; }
    );
    absent-policy-during-input-bump = validate { src = ./fixtures; } == [ ];
    absent-policy-string = validate { src = toString ./fixtures; } == [ ];
  };
  realErrors = import ../model-policy.nix {
    src = homelab-contracts;
    inherit roleMap;
    mlxCatalog = import ../../modules/mlx/catalog-data.nix;
  };
in
{
  model-policy =
    assert realErrors == [ ] || throw (builtins.concatStringsSep "\n" realErrors);
    helpers.mkDefaultsRegression {
      label = "model policy";
      checkName = "check-model-policy";
      checks = pkgs.lib.mapAttrsToList (name: actual: {
        inherit name actual;
        expected = true;
      }) cases;
    };
}
