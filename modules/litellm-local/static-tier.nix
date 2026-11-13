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
in
{
  routes = lib.concatMap (
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

  routerRungs = map (role: {
    model_name = routerRung role;
    litellm_params = {
      model = "openai/${role}";
      api_base = "os.environ/LLM_ROUTER_URL";
      api_key = "os.environ/OPENAI_API_KEY";
    };
  }) fallbackRoles;

  fallbacks = map (role: {
    ${role} = [ (routerRung role) ];
  }) fallbackRoles;

  contextWindowFallbacks = map (role: { ${role} = [ (routerRung role) ]; }) headRoles;
}
