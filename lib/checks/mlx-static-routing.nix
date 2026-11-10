# LiteLLM routing, local endpoint and cooldown rendering
# for resident aliases.
{
  pkgs,
  hmConfigStaticServing,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (hmConfigStaticServing.config.programs.litellmLocal) renderedConfig;
  routes = renderedConfig.model_list;
  routeFor = name: builtins.head (builtins.filter (route: route.model_name == name) routes);
  fallbackFor =
    group: lib.findFirst (entry: entry ? ${group}) null renderedConfig.litellm_settings.fallbacks;
  contracts = hmConfigStaticServing.config.programs.mlx.staticResidentContracts;
  qwen = contracts."mlx-community/Qwen3.8-27B-4bit";
  small9b = contracts."mlx-community/Qwen3.5-9B-OptiQ-4bit";
  judge = routeFor "judge";
  fast = routeFor "fast";
  default = routeFor "default";
  medium = routeFor "medium";
  mediumLocal = routeFor "medium-local";
in
{
  mlx-static-resident-routing =
    if
      judge.litellm_params.model == "openai/${small9b.model}"
      && judge.litellm_params.api_base == "http://127.0.0.1:${toString small9b.servicePort}/v1"
      && judge.litellm_params.timeout == small9b.timeoutSeconds
      && judge.litellm_params.stream_timeout == small9b.timeoutSeconds
      && judge.model_info.max_input_tokens == small9b.maxInputTokens
      && judge.model_info.max_output_tokens == small9b.maxOutputTokens
      && fast.litellm_params.model == judge.litellm_params.model
      && default.litellm_params.model == "openai/${qwen.model}"
      && default.litellm_params.api_base == "http://127.0.0.1:${toString qwen.servicePort}/v1"
      && medium.litellm_params.model == "openai/medium"
      && medium.litellm_params.api_base == "os.environ/LLM_ROUTER_URL"
      &&
        (fallbackFor "medium").medium == [
          "medium-local"
          "medium-homelab"
        ]
      && mediumLocal.litellm_params.model == "custom_openai/${qwen.model}"
      && mediumLocal.litellm_params.api_base == "os.environ/LOCAL_LLM_URL"
    then
      helpers.mkMarker "check-mlx-static-resident-routing" "LiteLLM routes resident aliases locally and preserves the router-first medium chain"
    else
      throw "static resident LiteLLM aliases must route locally with catalog-derived limits and preserve the router-first medium chain";

  mlx-static-resident-local-endpoint =
    if
      hmConfigStaticServing.config.programs.litellmLocal.localEndpoint
      == "http://127.0.0.1:${toString qwen.servicePort}/v1"
    then
      helpers.mkMarker "check-mlx-static-resident-local-endpoint" "LiteLLM local rungs call the default-role resident's loopback port"
    else
      throw "LiteLLM localEndpoint must be the default-role resident's loopback endpoint, got ${builtins.toJSON hmConfigStaticServing.config.programs.litellmLocal.localEndpoint}";

  mlx-static-resident-cooldowns =
    if
      (renderedConfig.router_settings.disable_cooldowns or false)
      && default.litellm_params.max_parallel_requests == qwen.concurrency
    then
      helpers.mkMarker "check-mlx-static-resident-cooldowns" "capped static resident routes render LiteLLM cooldown suppression"
    else
      throw "capped static resident routes must render LiteLLM router cooldown suppression";
}
