# litellm-local — bearer from a launch prefix instead of a token file.
#
# With services.aiStack.llmEndpointBearerFromEnv and
# programs.litellmLocal.launchPrefix, the proxy agent must start with the
# prefix and carry no OPENAI_API_KEY of its own. Without a
# prefix the same config must fail its assertion rather than start a proxy
# that has no bearer.
{
  pkgs,
  mkHmConfig,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  prefix = [
    "secret-wrapper"
    "--"
  ];
  mk =
    launchPrefix:
    mkHmConfig [
      {
        programs.litellmLocal = {
          inherit launchPrefix;
          enable = true;
        };
        services.aiStack = {
          llmEndpoint = "router";
          llmRouterEndpoint = "https://llm.example.invalid/v1";
          llmEndpointBearerFromEnv = true;
        };
      }
    ];
  agent = (mk prefix).config.launchd.agents.litellm-local.config;
  args = agent.ProgramArguments;
  noPrefixRejected =
    !(builtins.tryEval (builtins.deepSeq (mk [ ]).config.launchd.agents.litellm-local.config true))
    .success;
in
{
  litellm-local-launch-prefix =
    assert
      pkgs.lib.take 2 args == prefix
      || throw "litellm-local: launchPrefix must lead ProgramArguments; got ${builtins.toJSON args}";
    assert
      !(agent.EnvironmentVariables ? OPENAI_API_KEY)
      || throw "litellm-local: the proxy agent must not carry OPENAI_API_KEY in EnvironmentVariables";
    assert
      noPrefixRejected
      || throw "litellm-local: llmEndpointBearerFromEnv without launchPrefix must fail its assertion";
    helpers.mkMarker "check-litellm-local-launch-prefix" "litellm-local: launchPrefix leads the agent, the bearer comes only from the environment, and a missing prefix is rejected";
}
