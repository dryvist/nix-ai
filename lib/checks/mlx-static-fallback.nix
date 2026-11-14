# Static resident mode: every resident role falls through to its own router rung
# (`<role>-homelab`), which forwards the role name to the router. The `small`
# head alias also sends a request too large for its window to that rung.
{
  pkgs,
  hmConfigStaticServing,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (hmConfigStaticServing.config.programs.litellmLocal) renderedConfig;
  routeFor =
    name: builtins.head (builtins.filter (route: route.model_name == name) renderedConfig.model_list);
  rungFor = name: lib.findFirst (route: route.model_name == name) null renderedConfig.model_list;
  fallbackFor =
    group: lib.findFirst (entry: entry ? ${group}) null renderedConfig.litellm_settings.fallbacks;
  windowFallbackFor =
    group:
    lib.findFirst (
      entry: entry ? ${group}
    ) null renderedConfig.litellm_settings.context_window_fallbacks;
  small = routeFor "small";
  smallRouter = routeFor "small-homelab";
  smallNoThinking = routeFor "small-no-thinking";
  smallNoThinkingRung = rungFor "small-no-thinking-homelab";
  noThinkingBody = {
    chat_template_kwargs = {
      enable_thinking = false;
    };
  };
  contracts = hmConfigStaticServing.config.programs.mlx.staticResidentContracts;
  small9b = contracts."mlx-community/Qwen3.5-9B-OptiQ-4bit";
  residentRoles = lib.unique (
    lib.concatMap (contract: builtins.attrNames contract.roles) (builtins.attrValues contracts)
  );
  roleHasRouterFallback =
    role:
    let
      entry = fallbackFor role;
      rung = rungFor "${role}-homelab";
    in
    entry != null
    && entry.${role} == [ "${role}-homelab" ]
    && rung != null
    && rung.litellm_params.model == "openai/${role}"
    && rung.litellm_params.api_base == "os.environ/LLM_ROUTER_URL";
  rolesWithoutRouterFallback = builtins.filter (role: !(roleHasRouterFallback role)) residentRoles;
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
    then
      helpers.mkMarker "check-mlx-static-resident-router-fallback" "a stopped `small` resident falls back to the router under the same name, and an overflowing request goes there too"
    else
      throw "the `small` head alias must fall back to a router rung named small-homelab that forwards `small`, and overflow must reach it";

  mlx-static-role-router-fallbacks =
    if residentRoles != [ ] && rolesWithoutRouterFallback == [ ] then
      helpers.mkMarker "check-mlx-static-role-router-fallbacks" "every static resident role falls back to its own <role>-homelab router rung, which forwards the role name to the router"
    else
      throw "every static resident role must fall back to its <role>-homelab router rung; missing: ${builtins.toJSON rolesWithoutRouterFallback}";

  mlx-static-no-thinking-alias =
    if
      smallNoThinking.litellm_params.model == small.litellm_params.model
      && smallNoThinking.litellm_params.api_base == small.litellm_params.api_base
      && smallNoThinking.litellm_params.extra_body == noThinkingBody
      && smallNoThinking.model_info == small.model_info
      && !(small.litellm_params ? extra_body)
      && (fallbackFor "small-no-thinking")."small-no-thinking" == [ "small-no-thinking-homelab" ]
      && (windowFallbackFor "small-no-thinking")."small-no-thinking" == [ "small-no-thinking-homelab" ]
      && smallNoThinkingRung != null
      && smallNoThinkingRung.litellm_params.model == "openai/small"
      && smallNoThinkingRung.litellm_params.api_base == "os.environ/LLM_ROUTER_URL"
      && smallNoThinkingRung.litellm_params.extra_body == noThinkingBody
    then
      helpers.mkMarker "check-mlx-static-no-thinking-alias" "small-no-thinking shares the small resident's deployment and sends thinking-off per request; its overflow and router fallback forward small with the same body, and small keeps the worker default"
    else
      throw "small-no-thinking must mirror the small route with extra_body enable_thinking = false, fall back to small-no-thinking-homelab, which forwards small with the same body; small must carry no extra_body";
}
