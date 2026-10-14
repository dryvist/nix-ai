# Static resident routes and router fallbacks for the head aliases.
#
# Resident roles route locally unless `localModels` declares the same group.
# Head aliases use their same-named router group as the sole fallback.
#
# Each router rung is its own group (`<alias>-homelab`) because a fallback
# target must be a named group; the `*` wildcard cannot be one. A request too
# large for the resident's window goes to that same group.
{
  lib,
  staticResidentModels,
  admissionLimits,
  headAliases,
  localModels,
}:
let
  roles = lib.optionals (staticResidentModels != { }) headAliases;
  routerRung = role: "${role}-homelab";
  localModelDefinesRole = role: builtins.any (model: model.name == role) localModels;
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
        max_parallel_requests = admissionLimits.${modelId};
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
  }) roles;

  fallbacks = map (role: {
    ${role} = [ (routerRung role) ];
  }) roles;

  contextWindowFallbacks = map (role: { ${role} = [ (routerRung role) ]; }) roles;
}
