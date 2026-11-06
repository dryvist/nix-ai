# The OpenAI-compatible base URL Qwen Code talks to. Shared by settings.nix and
# the sandbox so the profile opens exactly the endpoint the client uses.
{ config }:
if config.programs.litellmLocal.enable then
  config.services.aiStack.localRouterUrl
else
  config.services.aiStack.resolvedLlmEndpoint
