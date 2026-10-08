# litellm-local — the endpoint the local rungs call.
#
# LOCAL_LLM_URL is the base URL every local rung calls. It must not be this
# proxy's own address, or a local rung calls LiteLLM itself.
{
  pkgs,
  hmConfigLitellmLocal,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  litellmLocal = hmConfigLitellmLocal.config.programs.litellmLocal;
  localEndpointIsNotProxy =
    litellmLocal.localEndpoint != "http://127.0.0.1:${toString litellmLocal.port}/v1";
in
{
  litellm-local-local-endpoint =
    assert
      localEndpointIsNotProxy
      || throw "programs.litellmLocal.localEndpoint must not be the proxy's own address, got ${builtins.toJSON litellmLocal.localEndpoint}";
    helpers.mkMarker "check-litellm-local-local-endpoint" "litellm-local: local rungs target a model server, not the proxy's own port";
}
