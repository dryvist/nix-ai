# The static resident host's routes and the router fallbacks of its head aliases.
#
# A resident role routes straight to its loopback worker as a singleton group.
# A head alias (`small`) instead keeps a way out of a stopped worker: this
# host's other local models that are a different model from the one the alias
# is resident on, then the same alias name on the shared router. Every other
# resident role stays a direct single-deployment route.
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
  residentModelOf =
    role:
    lib.findFirst (modelId: staticResidentModels.${modelId}.roles ? ${role}) null (
      builtins.attrNames staticResidentModels
    );
  routerRung = role: "${role}-homelab";
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
    }) (builtins.attrNames contract.roles)
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
    ${role} = map (m: m.name) (builtins.filter (m: m.id != residentModelOf role) localModels) ++ [
      (routerRung role)
    ];
  }) roles;

  contextWindowFallbacks = map (role: { ${role} = [ (routerRung role) ]; }) roles;
}
