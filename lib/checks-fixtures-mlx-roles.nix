# MLX role-map and cluster regression fixtures
{
  mkHmConfig,
  mkMlxRoleModel,
}:
{
  # Two evaluations for the role-registry check (lib/checks/mlx-catalog-roles.nix).
  # The first binds the `small` role to a swap-class entry; the second assigns
  # one role name to two enabled entries, so the uniqueness assertion must come
  # back false. Kept out of hmConfigCatalog so the duplicate case cannot leak
  # into the checks that read that fixture.
  hmConfigSmallRole = mkHmConfig [
    {
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
      programs.mlx.catalog = {
        qwen38-27b.class = "resident";
        mimo-9b = {
          class = "swap";
          roles = [ "small" ];
        };
      };
    }
  ];
  hmConfigDupRole = mkHmConfig [
    {
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
      programs.mlx.catalog = {
        qwen38-27b = {
          class = "resident";
          roles = [ "small" ];
        };
        mimo-9b = {
          class = "swap";
          roles = [ "small" ];
        };
      };
    }
  ];

  # Fourth evaluation exercising programs.mlx.clusterMode as the coordinator
  # (lib/checks/mlx-cluster.nix): rank env contract, watcher wiring, and the
  # catalog-rendered resident stop list.
  hmConfigCluster = mkHmConfig [
    {
      programs.mlx = {
        enable = true;
        roleMap = {
          models = {
            qwen38-27b = mkMlxRoleModel "qwen38-27b";
            mimo-9b = mkMlxRoleModel "mimo-9b";
          };
          roles = {
            default.model = "qwen38-27b";
            fast.model = "mimo-9b";
          };
          hosts.workstation = {
            resident = [
              "qwen38-27b"
              "mimo-9b"
            ];
            swap = [ ];
          };
        };
        catalog = {
          qwen38-27b = {
            class = "resident";
            roles = [ "default" ];
          };
          mimo-9b = {
            class = "resident";
            roles = [ "fast" ];
          };
        };
        clusterMode = {
          enable = true;
          role = "coordinator";
          modelCatalogKey = "glm47-reap50"; # gitleaks:allow (model catalog name, not a credential)
          # glm4_moe is pipeline-only; the clusterMode assertions now reject
          # tensor-parallel on it, so this fixture must name the real mode.
          shardingMode = "pipeline";
          shardMemoryMb = 1;
          wiredLimitMb = 90000;
          standaloneWiredLimitMb = 118000;
        };
      };
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];
}
