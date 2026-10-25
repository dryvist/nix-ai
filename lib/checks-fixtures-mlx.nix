# MLX catalog and static serving regression fixtures
{
  mkHmConfig,
  localMlxCatalog,
  mkMlxRoleModel,
}:
{
  # Third evaluation exercising programs.mlx.catalog (lib/checks/mlx.nix
  # mlx-catalog): a server-like selection plus one direct host override that
  # must beat the catalog's mkDefault.
  hmConfigCatalog = mkHmConfig [
    {
      programs.mlx = {
        catalog = {
          qwen38-27b = {
            class = "resident";
            roles = [ "judge" ];
          };
          # Swap-class text entry exercises its default ttl and model concurrency.
          mimo-9b.class = "swap";
          # OCR stays in the pinned role map and exercises the VLM backend.
          unlimited-ocr = {
            class = "swap";
            tweaks.ttl = 600;
          };
        };
        # Direct host setting on a catalog-managed key must win over the catalog.
        modelFlagOverrides."mlx-community/Qwen3.8-27B-4bit".cacheMemoryMb = 8192;
      };
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];

  # The MacBook production static-resident shape: both resident catalog
  # entries, the stable role mapping, and no swap-class selection.
  hmConfigStaticServing = mkHmConfig [
    {
      programs = {
        mlx = {
          enable = true;
          staticResidentLocalProxyConsumers = true;
          memoryHardLimitGb = 46;
          roleMap = {
            models = {
              qwen38-27b = mkMlxRoleModel "qwen38-27b";
              qwen35-9b = mkMlxRoleModel "qwen35-9b";
            };
            roles = {
              default.model = "qwen38-27b";
              fast.model = "qwen35-9b";
              judge.model = "qwen35-9b";
              recorder.model = "qwen35-9b";
              cheap.model = "qwen35-9b";
              small.model = "qwen35-9b";
            };
            hosts.workstation = {
              resident = [
                "qwen38-27b"
                "qwen35-9b"
              ];
              swap = [ ];
            };
          };
          catalog = {
            qwen38-27b = {
              class = "resident";
              roles = [ "default" ];
            };
            qwen35-9b = {
              class = "resident";
              roles = [
                "fast"
                "judge"
                "recorder"
                "cheap"
                "small"
              ];
            };
          };
        };
        litellmLocal = {
          enable = true;
          routerEntryModel = "medium";
          localModels = [
            {
              name = "medium";
              router = "medium";
            }
            {
              name = "medium-local";
              id = localMlxCatalog.qwen38-27b.model;
            }
          ];
        };
        qwen-code.enable = true;
      };
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];
}
