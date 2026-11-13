# Static resident routes and router fallbacks.
#
# Resident roles route locally unless `localModels` declares the same group.
# Every resident role that gets a route falls through to its own router rung
# (`<role>-homelab`) when the local deployment refuses or fails a request.
# Head aliases also send a request too large for the resident's window there.
#
# Each router rung is its own group (`<role>-homelab`) because a fallback
# target must be a named group; the `*` wildcard cannot be one.
#
# Each resident route admits as many requests as its worker decodes at once
# (the contract's `concurrency`); a request beyond that is refused immediately.
#
# A thinking-off sibling (`<role>-no-thinking`) of a role in `noThinkingRoles`
# is that role's route with `extra_body` set per request. It shares the same
# worker, so it inherits the same limits, and its own router rung carries the
# same body. Every other route keeps the worker's thinking default.
{
  lib,
  staticResidentModels,
  headAliases,
  localModels,
}:
let
  # Head aliases keep their overflow route. Empty when no resident is declared.
  headRoles = lib.optionals (staticResidentModels != { }) headAliases;
  routerRung = role: "${role}-homelab";
  localModelDefinesRole = role: builtins.any (model: model.name == role) localModels;
  # Roles that get a resident route on this host. A role a localModels rung
  # already names is served by that rung, so it has no static route.
  routedRoles = lib.unique (
    lib.concatMap (
      modelId:
      builtins.filter (role: !(localModelDefinesRole role)) (
        builtins.attrNames staticResidentModels.${modelId}.roles
      )
    ) (builtins.attrNames staticResidentModels)
  );
  # Every routed role gets a router rung and a fallback to it.
  fallbackRoles = lib.unique (headRoles ++ routedRoles);

  # Roles that also get a thinking-off sibling. Only a role this host routes.
  noThinkingRoles = builtins.filter (role: builtins.elem role routedRoles) [ "small" ];
  noThinkingName = role: "${role}-no-thinking";
  # LiteLLM merges a deployment's `extra_body` into the request JSON. The MLX
  # chat template reads `chat_template_kwargs` per request, which overrides the
  # worker's `--chat-template-args` default (enable_thinking = true).
  noThinkingBody = {
    chat_template_kwargs = {
      enable_thinking = false;
    };
  };

  residentRoutes = lib.concatMap (
    modelId:
    let
      contract = staticResidentModels.${modelId};
    in
    map (role: {
      model_name = role;
      litellm_params = {
        model = "openai/${modelId}";
        api_base = "http://127.0.0.1:${toString contract.servicePort}/v1";
        api_key = "os.environ/OPENAI_API_KEY";
        timeout = contract.timeoutSeconds;
        stream_timeout = contract.timeoutSeconds;
        max_parallel_requests = contract.concurrency;
      };
      model_info = {
        max_input_tokens = contract.maxInputTokens;
        max_output_tokens = contract.maxOutputTokens;
      };
    }) (builtins.filter (role: !(localModelDefinesRole role)) (builtins.attrNames contract.roles))
  ) (builtins.attrNames staticResidentModels);
in
{
  routes =
    residentRoutes
    ++ map (
      route:
      route
      // {
        model_name = noThinkingName route.model_name;
        litellm_params = route.litellm_params // {
          extra_body = noThinkingBody;
        };
      }
    ) (builtins.filter (route: builtins.elem route.model_name noThinkingRoles) residentRoutes);

  routerRungs =
    map (role: {
      model_name = routerRung role;
      litellm_params = {
        model = "openai/${role}";
        api_base = "os.environ/LLM_ROUTER_URL";
        api_key = "os.environ/OPENAI_API_KEY";
      };
    }) fallbackRoles
    ++ map (role: {
      model_name = routerRung (noThinkingName role);
      litellm_params = {
        model = "openai/${role}";
        api_base = "os.environ/LLM_ROUTER_URL";
        api_key = "os.environ/OPENAI_API_KEY";
        extra_body = noThinkingBody;
      };
    }) noThinkingRoles;

  fallbacks =
    map (role: {
      ${role} = [ (routerRung role) ];
    }) fallbackRoles
    ++ map (role: {
      ${noThinkingName role} = [ (routerRung (noThinkingName role)) ];
    }) noThinkingRoles;

  contextWindowFallbacks =
    map (role: { ${role} = [ (routerRung role) ]; }) headRoles
    ++ map (role: { ${noThinkingName role} = [ (routerRung (noThinkingName role)) ]; }) (
      builtins.filter (role: builtins.elem role headRoles) noThinkingRoles
    );
}
