# litellm-local — bearer from a launch prefix instead of a token file.
#
# With services.aiStack.llmEndpointBearerFromEnv and
# programs.litellmLocal.launchPrefix, the proxy agent starts with the prefix
# and carries no OPENAI_API_KEY of its own. An external process wrapper can
# also provide the bearer, so the module accepts env-bearer mode without its
# own launchPrefix; the start script still fails if the variable is missing.
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
  route =
    (mk prefix).config.programs.litellmLocal.renderedConfig.general_settings.pass_through_endpoints;
  args = agent.ProgramArguments;
  noPrefixAccepted =
    (builtins.tryEval (builtins.deepSeq (mk [ ]).config.launchd.agents.litellm-local.config true))
    .success;
  noPrefixRoute =
    (mk [ ]).config.programs.litellmLocal.renderedConfig.general_settings.pass_through_endpoints;
in
{
  litellm-local-launch-prefix =
    assert
      !(
        (mkHmConfig [ ]).config.programs.litellmLocal.renderedConfig.general_settings
          ? pass_through_endpoints
      )
      || throw "litellm-local: classifier pass-through must be absent without a router bearer";
    assert
      (mk prefix).config.programs.claude.settings.env.LITELLM_LOCAL_BASE_URL == (mk prefix)
      .config.programs.litellmLocal.rootUrl
      || throw "Claude Code must receive the local proxy root URL";
    assert
      route == [
        {
          path = "/v1/systemone";
          target = "${(mk prefix).config.services.aiStack.llmRouterEndpoint}/systemone";
          headers.Authorization = "Bearer os.environ/OPENAI_API_KEY";
        }
      ]
      || throw "litellm-local: classifier pass-through must use the router and process bearer";
    assert
      pkgs.lib.take 2 args == prefix
      || throw "litellm-local: launchPrefix must lead ProgramArguments; got ${builtins.toJSON args}";
    assert
      !(agent.EnvironmentVariables ? OPENAI_API_KEY)
      || throw "litellm-local: the proxy agent must not carry OPENAI_API_KEY in EnvironmentVariables";
    assert
      noPrefixAccepted
      || throw "litellm-local: external env-bearer delivery must not require the module's launchPrefix";
    assert
      noPrefixRoute == route
      || throw "litellm-local: external env-bearer delivery must enable router pass-through";
    assert
      !((mk [ ]).config.programs.claude.settings.env ? LLM_ROUTER_TOKEN_FILE)
      && !(pkgs.lib.hasInfix "LLM_ROUTER_TOKEN_FILE" (mk [ ]).config.programs.zsh.initContent)
      || throw "litellm-local: env-bearer mode must omit LLM_ROUTER_TOKEN_FILE from settings.json and shell init";
    helpers.mkMarker "check-litellm-local-launch-prefix" "litellm-local: module and external wrappers can deliver the bearer through the environment";
}
