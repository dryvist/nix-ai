# Verify that catalog admission limits reach LiteLLM's runtime semaphore.
{
  pkgs,
  hmConfigStaticServing,
  mkHmConfig,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  modelId = "mlx-community/Qwen3.8-27B-4bit";
  staticConfig = hmConfigStaticServing.config;
  baselineLimit = staticConfig.programs.mlx.modelAdmissionLimits.${modelId};
  admissionLimit = baselineLimit + 1;
  overrideConfig = mkHmConfig [
    {
      programs.mlx = {
        enable = true;
        staticResidentLocalProxyConsumers = true;
        catalog.qwen38-27b = {
          class = "resident";
          roles = [ "default" ];
        };
        modelAdmissionLimits.${modelId} = admissionLimit;
      };
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];
  defaultRoute =
    config:
    builtins.head (
      builtins.filter (
        route: route.model_name == "default"
      ) config.programs.litellmLocal.renderedConfig.model_list
    );
  baselineRoute = defaultRoute staticConfig;
  overrideRoute = defaultRoute overrideConfig.config;

  # A host that widens a worker admits the matching extra request: admission
  # and the resident contract follow modelConcurrencyLimits, not the catalog.
  widenedConfig = mkHmConfig [
    {
      programs.mlx = {
        enable = true;
        staticResidentLocalProxyConsumers = true;
        catalog.qwen38-27b = {
          class = "resident";
          roles = [ "default" ];
        };
        modelConcurrencyLimits.${modelId} = 2;
      };
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];
  widenedMlx = widenedConfig.config.programs.mlx;
  baselineQueue = baselineLimit - staticConfig.programs.mlx.modelConcurrencyLimits.${modelId};
in
{
  mlx-static-resident-admission =
    if
      baselineRoute.litellm_params.max_parallel_requests == baselineLimit
      && overrideRoute.litellm_params.max_parallel_requests == admissionLimit
      &&
        overrideRoute.litellm_params.max_parallel_requests
        != baselineRoute.litellm_params.max_parallel_requests
    then
      helpers.mkMarker "check-mlx-static-resident-admission" "catalog admission limits render into LiteLLM's per-deployment request semaphore"
    else
      throw "static resident LiteLLM routes must enforce the configured model admission limit";

  mlx-served-width-admission =
    if
      widenedMlx.modelAdmissionLimits.${modelId} == baselineQueue + 2
      && widenedMlx.staticResidentContracts.${modelId}.concurrency == 2
      && (defaultRoute widenedConfig.config).litellm_params.max_parallel_requests == baselineQueue + 2
    then
      helpers.mkMarker "check-mlx-served-width-admission" "a widened worker admits its served width plus the bounded queue and records that width in its resident contract"
    else
      throw "modelConcurrencyLimits must drive static resident admission and contract concurrency";
}
