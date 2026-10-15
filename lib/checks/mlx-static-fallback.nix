# Static resident mode: a head alias falls back to the router under its own name;
# every other resident role stays a direct route.
{
  pkgs,
  hmConfigStaticServing,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  renderedConfig = hmConfigStaticServing.config.programs.litellmLocal.renderedConfig;
  routeFor =
    name: builtins.head (builtins.filter (route: route.model_name == name) renderedConfig.model_list);
  fallbackFor =
    group: lib.findFirst (entry: entry ? ${group}) null renderedConfig.litellm_settings.fallbacks;
  windowFallbackFor =
    group:
    lib.findFirst (
      entry: entry ? ${group}
    ) null renderedConfig.litellm_settings.context_window_fallbacks;
  small = routeFor "small";
  smallRouter = routeFor "small-homelab";
  contracts = hmConfigStaticServing.config.programs.mlx.staticResidentContracts;
  small9b = contracts."mlx-community/Qwen3.5-9B-OptiQ-4bit";
in
{
  mlx-static-resident-router-fallback =
    if
      small.litellm_params.model == "openai/${small9b.model}"
      && small.litellm_params.api_base == "http://127.0.0.1:${toString small9b.servicePort}/v1"
      && (fallbackFor "small").small == [ "small-homelab" ]
      && (windowFallbackFor "small").small == [ "small-homelab" ]
      && smallRouter.litellm_params.model == "openai/small"
      && smallRouter.litellm_params.api_base == "os.environ/LLM_ROUTER_URL"
      && fallbackFor "judge" == null
      && fallbackFor "default" == null
    then
      helpers.mkMarker "check-mlx-static-resident-router-fallback" "a stopped `small` resident falls back to the router under the same name; other resident roles stay direct"
    else
      throw "the `small` head alias must fall back to a router rung named small-homelab that forwards `small`, and no other resident role may gain a fallback";
}
