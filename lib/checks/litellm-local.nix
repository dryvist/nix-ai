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
{ pkgs, hmConfig }:
let
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
}
