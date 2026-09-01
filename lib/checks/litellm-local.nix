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

  # Fallback-tier assertions live in their own file (12KB gate). They read the
  # litellm-local fixture rather than the bare base one: the tier's depth comes
  # from this host's declared local models, and the base fixture declares none,
  # so asserting against it would only ever prove the empty case.
  renderedTier = hmConfigLitellmLocal.config.programs.litellmLocal.renderedConfig;
  inherit
    (import ./litellm-local-fallbacks.nix {
      inherit lib;
      rendered = renderedTier;
    })
    firstFallbackFailure
    ;

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

  # Claude tier-name resolution + the wildcard leak gate (12KB gate).
  inherit
    (import ./litellm-local-claude-tier.nix {
      inherit
        lib
        claudeEnv
        rendered
        routerUrl
        tokenFilePath
        ;
    })
    claudeTierNames
    claudeTierNamesResolveLocally
    claudeTierNamesAre1m
    claudeShapedNamesCannotReachWildcard
    claudeHaikuUntouched
    claudeNoDiscovery
    claudeGetsRouterAddress
    claudeGetsTokenPathOnly
    ;

  # Under `claudeDirect` the proxy is out of Claude Code's path, so both the
  # base URL and the marker header are absent by design. The pair must move
  # together: a URL without the header is the 2026-08-24 outage, and a header
  # without the URL points at nothing.
  claudeDirect = enabled.programs.litellmLocal.claudeDirect;
  claudeHasBaseUrl = claudeEnv ? ANTHROPIC_BASE_URL;
  claudeHeaderIsMarker =
    if claudeDirect then
      !claudeHasBaseUrl && !(claudeEnv ? ANTHROPIC_CUSTOM_HEADERS)
    else
      claudeHasBaseUrl
      && claudeEnv.ANTHROPIC_CUSTOM_HEADERS == "x-litellm-api-key: Bearer ${clientToken}";

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

  # Nix evaluates lazily, so reading three attributes off one agent proves
  # nothing about the rest of the tree. A module argument that launchd.nix
  # required but default.nix never passed satisfied every assertion in this
  # file and only surfaced during `darwin-rebuild`, after a full flake check had
  # gone green. deepSeq forces the whole agent set, which is what makes a
  # missing argument or an undefined binding a check failure instead of a
  # rebuild failure.
  agentsFullyEvaluate = builtins.deepSeq enabled.launchd.agents true;
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
      || throw "a Claude Code tier name must resolve without `*`: a full claude-* id or an explicit model_list group. A bare alias (opus/sonnet/haiku, with or without [1m]) does not match claude-*, so it egresses to the router; got: ${builtins.toJSON claudeTierNames}";
    assert
      claudeTierNamesAre1m
      || throw "a claude-* tier id must carry [1m]: a subagent outgrows a 200k window, and an over-long request truncates into a confident wrong answer; got: ${builtins.toJSON claudeTierNames}";
    assert
      claudeShapedNamesCannotReachWildcard
      || throw "a Claude-shaped alias names a tier with no explicit model_list group, so it resolves through `*` and leaves for the router; got: ${builtins.toJSON claudeTierNames}";
    assert
      claudeHaikuUntouched
      || throw "Claude Code's haiku tier must stay on Anthropic: the `cheap` role's local target cannot hold Claude Code's system prompt, so an override fails every background call";
    assert
      claudeHeaderIsMarker
      || throw "Claude Code's proxy wiring is all-or-nothing: claudeDirect=false needs ANTHROPIC_BASE_URL plus the constant marker header `x-litellm-api-key: Bearer ${clientToken}` (what makes LiteLLM forward the OAuth bearer) on every surface; claudeDirect=true needs neither. Got direct=${lib.boolToString claudeDirect}, url ${
        if claudeHasBaseUrl then "set" else "unset"
      }, header ${claudeEnv.ANTHROPIC_CUSTOM_HEADERS or "unset"}";
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
    assert agentsFullyEvaluate || throw "unreachable: deepSeq either forces the agent tree or raises";
    assert
      agentCarriesNoSecret
      || throw "the launchd agent must take the router URL as plain env and read the bearer from its file at exec time, never as an EnvironmentVariable";
    helpers.mkMarker "check-litellm-local-client-wiring" "litellm-local: clients name roles, lead models untouched, every Claude Code setting non-secret and in settings.json";

  litellm-local-fallback-tier =
    assert firstFallbackFailure == null || throw firstFallbackFailure.msg;
    helpers.mkMarker "check-litellm-local-fallback-tier" "litellm-local: subagent tier is a cost-ordered chain of explicit groups, main tier never silently downgraded";
}
