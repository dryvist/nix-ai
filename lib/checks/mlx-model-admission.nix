# Verify that a static resident's LiteLLM route caps in-flight requests at the
# worker's decode concurrency, and that admission limits do not reach LiteLLM.
{
  pkgs,
  hmConfigStaticServing,
  mkHmConfig,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  modelId = "mlx-community/Qwen3.8-27B-4bit";
  staticConfig = hmConfigStaticServing.config;
  workerConcurrency = staticConfig.programs.mlx.modelConcurrencyLimits.${modelId};
  baselineAdmission = staticConfig.programs.mlx.modelAdmissionLimits.${modelId};
  admissionOverride = baselineAdmission + 1;
  overrideConfig = mkHmConfig [
    {
      programs.mlx = {
        enable = true;
        staticResidentLocalProxyConsumers = true;
        catalog.qwen38-27b = {
          class = "resident";
          roles = [ "default" ];
        };
        modelAdmissionLimits.${modelId} = admissionOverride;
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
  baselineQueue = baselineAdmission - workerConcurrency;
in
{
  mlx-static-resident-concurrency-cap =
    if
      baselineRoute.litellm_params.max_parallel_requests == workerConcurrency
      && workerConcurrency == staticConfig.programs.mlx.staticResidentContracts.${modelId}.concurrency
      && overrideRoute.litellm_params.max_parallel_requests == workerConcurrency
      && overrideConfig.config.programs.mlx.modelAdmissionLimits.${modelId} == admissionOverride
    then
      helpers.mkMarker "check-mlx-static-resident-concurrency-cap" "static resident LiteLLM routes cap in-flight requests at the worker's decode concurrency, and admission limits do not reach them"
    else
      throw "static resident LiteLLM routes must cap max_parallel_requests at modelConcurrencyLimits, independent of modelAdmissionLimits";

  mlx-served-width-concurrency-cap =
    if
      widenedMlx.modelAdmissionLimits.${modelId} == baselineQueue + 2
      && widenedMlx.staticResidentContracts.${modelId}.concurrency == 2
      && (defaultRoute widenedConfig.config).litellm_params.max_parallel_requests == 2
    then
      helpers.mkMarker "check-mlx-served-width-concurrency-cap" "a widened worker caps its LiteLLM route at its served width and records that width in its resident contract"
    else
      throw "modelConcurrencyLimits must drive the static resident LiteLLM cap and contract concurrency";
}
