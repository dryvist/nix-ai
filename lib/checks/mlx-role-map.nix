# Role-map contracts checked against the local catalog:
#   - every map model key is a catalog entry with the same physical id
#   - every map model exposes concurrency from the shared model catalog
#   - a dense model has concurrency 1
#   - every model a host class keeps, and every role it resolves, is declared
{
  pkgs,
  roleMap,
  hmConfigStaticServing,
  hmConfigCluster,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  catalog = import ../../modules/mlx/catalog-data.nix;
  mlxRoleModels = [
    "qwen38-27b"
    "mimo-9b"
  ];
  fixtureModels = hmConfig: hmConfig.config.programs.mlx.roleMap.models;
  fixtureHasChatServingMetadata =
    models:
    builtins.all (
      key:
      let
        model = models.${key};
        catalogEntry = catalog.${key};
      in
      model.id == catalogEntry.model
      && model.concurrency == catalogEntry.concurrency
      && model.serving.backend == "mlx-lm"
      && model.serving.endpoint == "/v1/chat/completions"
      && model.mlxChat
    ) mlxRoleModels;
  missingConcurrency = builtins.filter (key: !(roleMap.models.${key} ? concurrency)) (
    builtins.attrNames roleMap.models
  );
  embedding = import ../../lib/model-serving.nix {
    catalogEntry = {
      stage0.serving = {
        runtime = "mlx-vlm";
        endpoint = "/v1/embeddings";
      };
    };
  };
  systemOne = import ../../lib/model-serving.nix {
    catalogEntry = {
      stage0.serving = {
        runtime = "opendecider[serve]";
        endpoint = "/v1/systemone";
      };
    };
  };
  laya = import ../../lib/model-serving.nix {
    catalogEntry = {
      stage0.serving = {
        runtime = "laya-serve";
        endpoint = "/v1/systemone";
      };
    };
  };
  mlxLanguageModel = import ../../lib/model-serving.nix {
    catalogEntry.profiles.mlx = { };
    mlxCatalogEntry = { };
  };
  mlxVisionLanguageModel = import ../../lib/model-serving.nix {
    catalogEntry = { };
    mlxCatalogEntry.backend = "mlx-vlm";
  };
  embeddingOnChatBackend = import ../../lib/model-serving.nix {
    catalogEntry = {
      stage0.serving = {
        runtime = "mlx-vlm";
        endpoint = "/v1/embeddings";
      };
    };
    mlxCatalogEntry.backend = "mlx-vlm";
  };

  stage0RoleMap = {
    models = {
      stage0_embedding = {
        id = "nativ-community/embeddinggemma-2-mxfp8";
        concurrency = 4;
      }
      // embedding;
      stage0_systemone_opendecider = {
        id = "manjunathshiva/opendecider-nano";
        concurrency = 4;
      }
      // systemOne;
      stage0_systemone_laya = {
        id = "convaiinnovations/laya-typed-decisions";
        concurrency = 4;
      }
      // laya;
    };
    roles = {
      stage0_embedding = {
        model = "stage0_embedding";
        egress = "none";
      };
      stage0_systemone_opendecider = {
        model = "stage0_systemone_opendecider";
        egress = "none";
      };
      stage0_systemone_laya = {
        model = "stage0_systemone_laya";
        egress = "none";
      };
    };
    hosts = {
      workstation = {
        resident = [ ];
        swap = [
          "stage0_embedding"
          "stage0_systemone_opendecider"
          "stage0_systemone_laya"
        ];
      };
    };
  };
  errorsFor =
    candidate:
    import ../../modules/mlx/role-map-errors.nix {
      inherit catalog;
      roleMap = candidate;
    };

  realErrors = errorsFor roleMap;
  callerRoleMapWithoutMlxChat = roleMap // {
    models = roleMap.models // {
      mimo-9b = builtins.removeAttrs roleMap.models.mimo-9b [ "mlxChat" ];
    };
  };
  callerRoleMapWithExplicitFalse = roleMap // {
    models = roleMap.models // {
      mimo-9b = roleMap.models.mimo-9b // {
        mlxChat = false;
      };
    };
  };
  callerRoleMapWithWrongCatalogId = roleMap // {
    models = roleMap.models // {
      mimo-9b = roleMap.models.mimo-9b // {
        id = "mlx-community/not-the-catalog-model";
        mlxChat = true;
      };
    };
  };

  unknownModel = roleMap // {
    models = roleMap.models // {
      not-in-catalog = {
        id = "mlx-community/not-in-catalog";
        concurrency = 1;
        serving = {
          backend = "mlx-lm";
          endpoint = "/v1/chat/completions";
        };
        mlxChat = true;
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
      missingConcurrency == [ ]
      || throw "role map models have no catalog concurrency: ${builtins.toJSON missingConcurrency}";
    assert
      realErrors == [ ]
      || throw "role map: the pinned homelab-contracts map breaks the catalog contract: ${builtins.toJSON realErrors}";
    assert
      fixtureHasChatServingMetadata (fixtureModels hmConfigStaticServing)
      && fixtureHasChatServingMetadata (fixtureModels hmConfigCluster)
      || throw "role map: static-serving and cluster fixtures must derive current catalog chat metadata";
    assert
      embedding.serving.endpoint == "/v1/embeddings"
      && !embedding.mlxChat
      && systemOne.serving.endpoint == "/v1/systemone"
      && !systemOne.mlxChat
      && laya.serving.runtime == "laya-serve"
      && !laya.mlxChat
      && mlxLanguageModel.serving.backend == "mlx-lm"
      && mlxLanguageModel.mlxChat
      && mlxVisionLanguageModel.serving.backend == "mlx-vlm"
      && mlxVisionLanguageModel.mlxChat
      && !embeddingOnChatBackend.mlxChat
      || throw "role map: runtime and endpoint metadata must separate chat models from embedding and system-one models";
    assert
      errorsFor stage0RoleMap == [ ]
      && stage0RoleMap.models.stage0_embedding.serving.runtime == "mlx-vlm"
      && stage0RoleMap.models.stage0_systemone_opendecider.serving.endpoint == "/v1/systemone"
      || throw "role map: non-MLX runtime records must remain available to their consumers";
    assert
      errorsFor callerRoleMapWithoutMlxChat == [ ]
      && reports callerRoleMapWithExplicitFalse ".*model `mimo-9b` has an MLX catalog entry without a chat-completion backend.*"
      && reports callerRoleMapWithWrongCatalogId ".*model `mimo-9b` id .* differs from catalog .*"
      || throw "role map: missing chat metadata derives from a matching catalog entry; explicit false and mismatched ids remain invalid";
    assert
      reports unknownModel ".*not-in-catalog.*not a catalog entry.*"
      || throw "role map: a model key absent from the catalog must be reported";
    assert
      reports denseParallel ".*dense model `qwen38-27b` must have concurrency 1.*"
      || throw "role map: a dense model with concurrency 2 must be reported";
    assert
      reports undeclaredHostModel ".*host class `server` keeps undeclared model `undeclared-model`.*"
      || throw "role map: a host class keeping an undeclared model must be reported";
    helpers.mkMarker "check-mlx-role-map" "role map: missing chat metadata derives from catalog; invalid catalog, concurrency and host-class cases are reported";
}
