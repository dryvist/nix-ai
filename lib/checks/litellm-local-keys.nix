# litellm-local — proxy auth and per-deployment api_key scoping.
#
# Split out of lib/checks/litellm-local.nix for the per-file 12KB gate (the
# same split-rather-than-exempt pattern used across lib/checks). Pure
# predicates over the already-rendered config; the parent asserts them with
# the failure messages that explain each one.
{ rendered }:
let
  noGlobalForwarding =
    !(rendered ? general_settings) || !(rendered.general_settings ? forward_client_headers_to_llm_api);

  # No master key, by design: a subscription Claude Code session may send the
  # gateway no credential variable, and settings.json (the only channel that
  # reaches every session) cannot carry a secret. With a master key present,
  # LiteLLM treats the OAuth bearer as a virtual key and answers
  # `400 No connected db` — the outage's exact symptom.
  noMasterKey = !(rendered ? general_settings) || !(rendered.general_settings ? master_key);

  # LiteLLM 1.105 refuses to boot with no master key unless this is set.
  permitsUnsetMasterKey =
    (rendered.general_settings.dangerously_permit_weak_or_unset_master_key or false) == true;

  # The first violated master-key rule, or null.
  masterKeyFailure =
    if !noMasterKey then
      "litellm-local must not set a master_key: a subscription Claude Code session cannot send a gateway credential, and settings.json cannot carry a secret, so a master key makes LiteLLM treat the OAuth bearer as a virtual key (400 No connected db)"
    else if !permitsUnsetMasterKey then
      "litellm-local must set general_settings.dangerously_permit_weak_or_unset_master_key: LiteLLM 1.105 refuses to boot with no master key, and this proxy takes none by design"
    else
      null;

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

  # LiteLLM substitutes only the matched tail of a wildcard into the target,
  # so `anthropic/*` sent `claude-opus-5` upstream as `opus-5`. The target
  # must repeat the prefix.
  claudeKeepsPrefix = claudeDeployment.litellm_params.model == "anthropic/claude-*";
in
{
  # The parent's failure message quotes the actual compiled target.
  claudeTargetModel = claudeDeployment.litellm_params.model;

  inherit
    noGlobalForwarding
    masterKeyFailure
    wildcardHasOwnKey
    claudeHasNoKey
    claudeKeepsPrefix
    ;
}
