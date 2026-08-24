# Local LiteLLM proxy regression tests
#
# The safety property this file exists for: the local proxy forwards the
# calling client's own credentials to the `claude-*` deployment ONLY. That
# deployment reaches Anthropic directly with the client's own credentials;
# the wildcard deployment reaches a shared router. Forwarding the first leg's
# credential onto the second is the one unacceptable outcome, and the only
# thing standing between them is the scoped
# `litellm_settings.model_group_settings.forward_client_headers_to_llm_api`
# list. So assert on that list directly, and assert that the global
# `general_settings.forward_client_headers_to_llm_api` boolean — which would
# forward to EVERY deployment, router leg included — is absent.
#
# Reads programs.litellmLocal.renderedConfig, which the module sets
# unconditionally, so this needs no second home-manager evaluation.
{
  pkgs,
  hmConfig,
  hmConfigLitellmLocal,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };

  rendered = hmConfig.config.programs.litellmLocal.renderedConfig;

  forwardList = rendered.litellm_settings.model_group_settings.forward_client_headers_to_llm_api;

  scopedToClaudeOnly = forwardList == [ "claude-*" ];

  noGlobalForwarding = !(rendered.general_settings ? forward_client_headers_to_llm_api);

  # The wildcard deployment must carry its own api_key, so it authenticates to
  # the router as itself rather than relying on whatever a client sent.
  wildcardDeployment = builtins.head (builtins.filter (m: m.model_name == "*") rendered.model_list);
  claudeDeployment = builtins.head (
    builtins.filter (m: m.model_name == "claude-*") rendered.model_list
  );

  wildcardHasOwnKey = wildcardDeployment.litellm_params ? api_key;

  # Conversely the claude-* deployment must NOT carry one: a key here would
  # override the forwarded client credential and silently bill the wrong
  # account.
  claudeHasNoKey = !(claudeDeployment.litellm_params ? api_key);

  # ---- enabled-path wiring -------------------------------------------------
  enabled = hmConfigLitellmLocal.config;
  proxyBase = enabled.programs.litellmLocal.baseUrl;

  claudeEnv = enabled.programs.claude.settings.env;

  # The main model must stay on Anthropic: only the subagent and background
  # tiers are repointed at roles.
  claudeMainUntouched = !(claudeEnv ? ANTHROPIC_MODEL);

  claudeSubagentRole = claudeEnv.CLAUDE_CODE_SUBAGENT_MODEL == "subagent";
  claudeHaikuRole = claudeEnv.ANTHROPIC_DEFAULT_HAIKU_MODEL == "cheap";

  # The proxy master key must never be rendered into settings.json, which is
  # a world-readable file in the Nix store. The module exports the header at
  # shell init instead.
  claudeNoHeaderInStore = !(claudeEnv ? ANTHROPIC_CUSTOM_HEADERS);

  # Codex must gain the proxy as an ADDITIONAL provider without the default
  # provider or model changing.
  codexAgent = enabled.programs.codex;
  codexDefaultUntouched = codexAgent.modelProvider == hmConfig.config.programs.codex.modelProvider;

  # Every CLI that reads an OpenAI-compatible base URL points at the proxy.
  fabricBase = enabled.home.sessionVariables.OPENAI_API_BASE_URL == proxyBase;
  fabricRole = enabled.home.sessionVariables.DEFAULT_MODEL == "cheap";

  # The Gemini-format client appends `/v1beta/...` itself, so it must get the
  # root URL, not the OpenAI-compatible `/v1` base.
  agyBase = enabled.home.sessionVariables.GOOGLE_GEMINI_BASE_URL;
  agyGetsRoot = agyBase == enabled.programs.litellmLocal.rootUrl && !lib.hasSuffix "/v1" agyBase;

  agent = enabled.launchd.agents.litellm-local.config;
  agentLoopbackOnly = enabled.programs.litellmLocal.port == 4100;
  # The router URL reaches the agent as plain env; the two secrets do not.
  agentCarriesNoSecret =
    (agent.EnvironmentVariables ? LLM_ROUTER_URL)
    && !(agent.EnvironmentVariables ? OPENAI_API_KEY)
    && !(agent.EnvironmentVariables ? LITELLM_LOCAL_KEY);
in
{
  litellm-local-header-scope =
    assert
      scopedToClaudeOnly
      || throw "litellm-local must forward client headers to the claude-* group ONLY (a forwarded client credential must never reach the router leg); got: ${builtins.toJSON forwardList}";
    assert
      noGlobalForwarding
      || throw "litellm-local must not set general_settings.forward_client_headers_to_llm_api: that boolean forwards to every deployment, including the router leg";
    assert
      claudeHasNoKey
      || throw "the litellm-local claude-* deployment must carry no api_key so the forwarded client credential is what authenticates it";
    assert
      wildcardHasOwnKey
      || throw "the litellm-local wildcard deployment must carry its own api_key so it authenticates to the router as itself";
    helpers.mkMarker "check-litellm-local-header-scope" "litellm-local: client-header forwarding scoped to claude-* only, router leg authenticates with its own key";

  litellm-local-client-wiring =
    assert
      claudeMainUntouched
      || throw "enabling the proxy must not pin Claude Code's main model; ANTHROPIC_MODEL was set";
    assert
      claudeSubagentRole || throw "Claude Code's subagent tier must resolve to the `subagent` role";
    assert claudeHaikuRole || throw "Claude Code's background tier must resolve to the `cheap` role";
    assert
      claudeNoHeaderInStore
      || throw "ANTHROPIC_CUSTOM_HEADERS must not be rendered into settings.json: it carries the proxy master key, and settings.json lands in the Nix store";
    assert
      codexDefaultUntouched
      || throw "enabling the proxy must not change Codex's default model provider; the `ox` profile is the opt-in";
    assert fabricBase || throw "fabric must read the proxy through OPENAI_API_BASE_URL";
    assert fabricRole || throw "fabric's default model must be the `cheap` role via DEFAULT_MODEL";
    assert
      agyGetsRoot
      || throw "the Gemini-format client must get the proxy root URL, not the /v1 OpenAI base: it appends /v1beta/models/<model>:generateContent itself; got: ${agyBase}";
    assert agentLoopbackOnly || throw "the proxy port default must stay 4100";
    assert
      agentCarriesNoSecret
      || throw "the launchd agent must take the router URL as plain env and read both secrets from files at exec time, never as EnvironmentVariables";
    helpers.mkMarker "check-litellm-local-client-wiring" "litellm-local: clients name roles, lead models untouched, no secret rendered into the store";
}
