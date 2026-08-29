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
# The second property is the one the 2026-08-24 outage taught: everything a
# Claude Code session needs to reach the proxy must travel in settings.json,
# and therefore must be non-secret. A proxy credential cannot satisfy both, so
# the proxy takes none, and the one header LiteLLM needs is a constant marker.
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

  # Cost-ordered fallback-tier assertions live in their own file (12KB gate).
  firstFallbackFailure =
    (import ./litellm-local-fallbacks.nix { inherit lib rendered; }).firstFallbackFailure;

  # Proxy auth + per-deployment api_key scoping (12KB gate).
  keys = import ./litellm-local-keys.nix { inherit rendered; };
  inherit (keys) claudeTargetModel;
  inherit (keys)
    noGlobalForwarding
    noMasterKey
    wildcardHasOwnKey
    claudeHasNoKey
    claudeKeepsPrefix
    ;

  forwardList = rendered.litellm_settings.model_group_settings.forward_client_headers_to_llm_api;

  scopedToClaudeOnly = forwardList == [ "claude-*" ];

  # ---- enabled-path wiring -------------------------------------------------
  enabled = hmConfigLitellmLocal.config;
  proxyBase = enabled.programs.litellmLocal.baseUrl;
  clientToken = enabled.programs.litellmLocal.clientToken;
  tokenFilePath = toString enabled.services.aiStack.llmEndpointTokenFile;
  routerUrl = enabled.services.aiStack.llmRouterEndpoint;

  claudeEnv = enabled.programs.claude.settings.env;

  # The main model must stay on Anthropic: only the subagent and background
  # tiers are repointed at roles.
  claudeMainUntouched = !(claudeEnv ? ANTHROPIC_MODEL);

  # Every model name Claude Code is pointed at must be one the proxy can resolve
  # WITHOUT the `*` wildcard — either an Anthropic capability alias / model id
  # that lands in the `claude-*` group, or an explicit `model_name` in the
  # model_list. Naming an upstream ROLE is what caused the outage: the router
  # served no `subagent` group, so the request fell through `*` and 404'd on
  # every subagent spawn. `*` must never be what makes a Claude Code tier work.
  explicitGroups = map (d: d.model_name) rendered.model_list;
  claudeTierNames = lib.filter (n: n != null) [
    (claudeEnv.CLAUDE_CODE_SUBAGENT_MODEL or null)
    (claudeEnv.ANTHROPIC_MODEL or null)
  ];
  claudeTierNamesResolveLocally = lib.all (
    n:
    lib.hasPrefix "claude" n
    || lib.elem n [
      "opus"
      "sonnet"
      "haiku"
    ]
    || lib.elem n explicitGroups
  ) claudeTierNames;

  # The haiku tier stays on Anthropic: Claude Code's background requests carry
  # its full system prompt (~36k tokens), which the `cheap` role's 32k-window
  # local target cannot hold, so an override fails every background call.
  claudeHaikuUntouched = !(claudeEnv ? ANTHROPIC_DEFAULT_HAIKU_MODEL);

  # The header is what makes LiteLLM forward the OAuth bearer instead of
  # treating it as the proxy credential. It must be in settings.json (every
  # surface) and it must be the constant marker, never a key.
  claudeHeaderIsMarker =
    claudeEnv.ANTHROPIC_CUSTOM_HEADERS == "x-litellm-api-key: Bearer ${clientToken}";

  # Discovery would list the two wildcard groups as picker rows.
  claudeNoDiscovery = !(claudeEnv ? CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY);

  # The private-workspace guard asks the upstream router what a role resolves
  # to; it must find the address and the bearer file PATH from settings.json,
  # since a GUI-launched session never runs shell init.
  claudeGetsRouterAddress = claudeEnv.LLM_ROUTER_URL == routerUrl;
  claudeGetsTokenPathOnly = claudeEnv.LLM_ROUTER_TOKEN_FILE == tokenFilePath;

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

  # Shell callers get the same router address and bearer-file PATH, and the
  # placeholder every OpenAI-compatible client sends the proxy. The token
  # file's CONTENTS must never be exported under the router-token name.
  zshInit = enabled.programs.zsh.initContent;
  exportsRouterUrl = lib.hasInfix "export LLM_ROUTER_URL=" zshInit;
  exportsTokenFilePath = lib.hasInfix "export LLM_ROUTER_TOKEN_FILE=" zshInit;
  tokenFileIsPathOnly = lib.hasInfix "export LLM_ROUTER_TOKEN_FILE=${tokenFilePath}" zshInit;
  exportsPlaceholder = lib.hasInfix "export LITELLM_LOCAL_KEY=${clientToken}" zshInit;

  agent = enabled.launchd.agents.litellm-local.config;
  agentLoopbackOnly = enabled.programs.litellmLocal.port == 4100;
  # The router URL reaches the agent as plain env; the bearer does not — the
  # wrapper reads it from the file at exec time.
  agentCarriesNoSecret =
    (agent.EnvironmentVariables ? LLM_ROUTER_URL) && !(agent.EnvironmentVariables ? OPENAI_API_KEY);
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
      noMasterKey
      || throw "litellm-local must not set a master_key: a subscription Claude Code session cannot send a gateway credential, and settings.json cannot carry a secret, so a master key makes LiteLLM treat the OAuth bearer as a virtual key (400 No connected db)";
    assert
      claudeHasNoKey
      || throw "the litellm-local claude-* deployment must carry no api_key so the forwarded client credential is what authenticates it";
    assert
      claudeKeepsPrefix
      || throw "the litellm-local claude-* deployment must target anthropic/claude-*: LiteLLM substitutes only the matched tail, so anthropic/* sends claude-opus-5 upstream as opus-5; got: ${claudeTargetModel}";
    assert
      wildcardHasOwnKey
      || throw "the litellm-local wildcard deployment must carry its own api_key so it authenticates to the router as itself";
    helpers.mkMarker "check-litellm-local-header-scope" "litellm-local: client-header forwarding scoped to claude-* only, no proxy credential, router leg authenticates with its own key";

  litellm-local-client-wiring =
    assert
      claudeMainUntouched
      || throw "enabling the proxy must not pin Claude Code's main model; ANTHROPIC_MODEL was set";
    assert
      claudeTierNamesResolveLocally
      || throw "every model name Claude Code is pointed at must resolve without the `*` wildcard — an Anthropic alias (opus/sonnet/haiku), a claude-* id, or an explicit model_list group. Naming an upstream ROLE 404s every call in that tier the moment the router stops serving it; got: ${builtins.toJSON claudeTierNames}";
    assert
      claudeHaikuUntouched
      || throw "Claude Code's haiku tier must stay on Anthropic: the `cheap` role's local target cannot hold Claude Code's system prompt, so an override fails every background call";
    assert
      claudeHeaderIsMarker
      || throw "settings.json must carry ANTHROPIC_CUSTOM_HEADERS as the constant marker `x-litellm-api-key: Bearer ${clientToken}`: it is what makes LiteLLM forward the OAuth bearer, and it must reach every session surface; got: ${
        claudeEnv.ANTHROPIC_CUSTOM_HEADERS or "<unset>"
      }";
    assert
      claudeNoDiscovery
      || throw "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY must stay unset: the proxy's /v1/models lists wildcard groups, not models";
    assert
      claudeGetsRouterAddress
      || throw "settings.json must carry LLM_ROUTER_URL so the private-workspace guard can ask the upstream router what a role resolves to from every session surface";
    assert
      claudeGetsTokenPathOnly
      || throw "settings.json must carry LLM_ROUTER_TOKEN_FILE as the bearer file's PATH, never its contents";
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
      exportsRouterUrl
      || throw "shell init must export LLM_ROUTER_URL so a caller can reach the upstream router directly; the local wildcard hides what a role resolves to";
    assert
      exportsTokenFilePath
      || throw "shell init must export LLM_ROUTER_TOKEN_FILE so a caller has a file to read the router bearer from";
    assert
      tokenFileIsPathOnly
      || throw "LLM_ROUTER_TOKEN_FILE must carry the PATH of the bearer file, never its contents";
    assert
      exportsPlaceholder
      || throw "shell init must export LITELLM_LOCAL_KEY as the constant placeholder `${clientToken}`; the proxy checks no credential and OpenAI-compatible SDKs refuse an empty key";
    assert
      agentCarriesNoSecret
      || throw "the launchd agent must take the router URL as plain env and read the bearer from its file at exec time, never as an EnvironmentVariable";
    helpers.mkMarker "check-litellm-local-client-wiring" "litellm-local: clients name roles, lead models untouched, every Claude Code setting non-secret and in settings.json";

  litellm-local-fallback-tier =
    assert firstFallbackFailure == null || throw firstFallbackFailure.msg;
    helpers.mkMarker "check-litellm-local-fallback-tier" "litellm-local: subagent tier is a cost-ordered chain of explicit groups, main tier never silently downgraded";
}
