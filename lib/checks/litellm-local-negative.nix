# litellm-local — negative cases.
#
# Every other litellm-local check proves a correct config renders correctly.
# These two prove the guards that catch a WRONG config still fire. Remove the
# fix each one names and the case here stops failing, which is the only way a
# guard is worth having.
#
# Split from lib/checks/litellm-local.nix for the per-file 12KB gate.
{
  pkgs,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };

  # ---- empty model_list must fail as a check, not as a builtins error ------
  # `lib.last` throws on an empty list. Without the guard in
  # litellm-local-fallbacks.nix this evaluation raises
  # `lists.last: list must not be empty!`, aborting the suite with a stack
  # trace instead of the terminal-rung check's own message.
  #
  # Read through the exported flag rather than `firstFallbackFailure`: that
  # helper returns the FIRST failing check, and an empty model_list already
  # fails the explicit-groups check well before the terminal one, so the guard
  # is unreachable through it.
  emptyModelListIsFalseNotThrow =
    (import ./litellm-local-fallbacks.nix {
      inherit lib;
      rendered = {
        model_list = [ ];
        litellm_settings.num_retries = 3;
      };
    }).terminalNamesUpstreamGroup == false;

  # ---- routerEntryModel must be a plain router group name -----------------
  # One fixture, one variable. Everything else is valid, so a failed
  # evaluation can only be the routerEntryModel assertion -- and the positive
  # control below proves the fixture itself is sound. home-manager throws on
  # ANY failed assertion the moment `config` is touched, so catch it with
  # tryEval rather than reading `config.assertions`, which throws first.
  routerEntryEvaluates =
    routerEntryModel:
    let
      cfg = mkHmConfig [
        {
          programs.litellmLocal = {
            inherit routerEntryModel;
            enable = true;
            localModels = [
              {
                name = "subagent";
                id = "test-local/small-4bit";
                contextWindow = 131072;
              }
            ];
          };
          services.aiStack = {
            llmEndpoint = "router";
            llmRouterEndpoint = "https://llm.example.invalid/v1";
            llmEndpointTokenFile = "/run/secrets/LLM_ROUTER_BEARER";
          };
        }
      ];
    in
    (builtins.tryEval (builtins.deepSeq cfg.config.programs.litellmLocal.renderedConfig true)).success;

  # Null, empty, and provider-prefixed all render cleanly and all 404 at
  # runtime; only a bare group name is valid.
  rejectedRouterEntries = [
    null
    ""
    "openai/x"
  ];
  everyBadRouterEntryRejected = lib.all (v: routerEntryEvaluates v == false) rejectedRouterEntries;
  plainGroupNameAccepted = routerEntryEvaluates "test-router-entry";
in
{
  litellm-local-negative =
    assert
      emptyModelListIsFalseNotThrow
      || throw "an empty model_list must make the terminal-rung check FALSE, not throw: restore the `renderedList == [ ]` guard around `lib.last` in lib/checks/litellm-local-fallbacks.nix";
    assert
      everyBadRouterEntryRejected
      || throw "programs.litellmLocal.routerEntryModel must reject null, \"\" and a provider-prefixed value while localModels is non-empty; got evaluation results ${builtins.toJSON (map routerEntryEvaluates rejectedRouterEntries)}";
    assert
      plainGroupNameAccepted
      || throw "a plain router group name must satisfy the routerEntryModel assertion; got ${builtins.toJSON plainGroupNameAccepted}";
    helpers.mkMarker "check-litellm-local-negative" "litellm-local: an empty model_list fails as a check not a throw, and routerEntryModel rejects null/empty/provider-prefixed";
}
