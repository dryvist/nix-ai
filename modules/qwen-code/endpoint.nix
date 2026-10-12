# The OpenAI-compatible base URL Qwen Code talks to: the local proxy when it is
# enabled, otherwise the stack's resolved endpoint. Shared by settings.nix and
# the sandbox so the profile opens exactly the loopback port the client uses.
{ config }:
let
  inherit (config.programs) litellmLocal;
in
if litellmLocal.enable then litellmLocal.baseUrl else config.services.aiStack.resolvedLlmEndpoint
