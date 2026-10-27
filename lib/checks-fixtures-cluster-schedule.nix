# Two evaluations with programs.mlx.clusterMode.schedule switched on, for
# ./checks/mlx-cluster-schedule.nix: a coordinator and a worker. Split out of
# ./checks-fixtures.nix, which is at its per-file size ceiling. The cluster body
# mirrors hmConfigCluster there. Only the role and the schedule differ.
{ mkHmConfig }:
let
  localMlxCatalog = import ../modules/mlx/catalog-data.nix;
  mkMlxRoleModel =
    key:
    let
      entry = localMlxCatalog.${key};
    in
    {
      id = entry.model;
      inherit (entry) concurrency;
    }
    // import ./model-serving.nix {
      catalogEntry = { };
      mlxCatalogEntry = entry;
    };
  clusterModule = role: {
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
        inherit role;
        modelCatalogKey = "glm47-reap50";
        # glm4_moe is pipeline-only, so the sharding mode must name it.
        shardingMode = "pipeline";
        shardMemoryMb = 1;
        wiredLimitMb = 90000;
        standaloneWiredLimitMb = 118000;
        schedule.enable = true;
      };
    };
    programs.litellmLocal.enable = true;
    services.aiStack = {
      llmEndpoint = "router";
      llmRouterEndpoint = "https://router.example.invalid/v1";
      llmEndpointTokenFile = "/tmp/test-router-token";
    };
  };
in
{
  hmConfigClusterScheduled = mkHmConfig [ (clusterModule "coordinator") ];
  hmConfigClusterScheduledWorker = mkHmConfig [ (clusterModule "worker") ];
}
