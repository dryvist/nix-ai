# litellm-local — isolated fallback chains (programs.litellmLocal.isolatedChains).
#
# The property this file pins: a chain falls through only to its own rungs. The
# shared router's terminal rung is the cloud escape, so no qwen-* ladder may
# name it, in fallbacks or in context_window_fallbacks. The two negative cases
# at the bottom prove the guards that reject a chain built wrong still fire.
{
  pkgs,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };

  qwenChain = [
    {
      name = "qwen-local";
      id = "mlx-community/Qwen3.8-27B-4bit";
    }
    {
      name = "qwen-homelab";
      router = "qwen3.8-27b";
      contextWindow = 32768;
    }
  ];

  # The catalog supplies qwen-local's window, through the same derivation a
  # localModels rung uses, so the escape has a real number to fire on.
  mkChainConfig =
    chains:
    mkHmConfig [
      {
        programs = {
          litellmLocal = {
            enable = true;
            localEndpoint = "http://127.0.0.1:18080/v1";
            isolatedChains = chains;
          };
          mlx.modelContextWindows."mlx-community/Qwen3.8-27B-4bit" = 32768;
        };
        services.aiStack = {
          llmEndpoint = "router";
          llmRouterEndpoint = "https://llm.example.invalid/v1";
          llmEndpointTokenFile = "/run/secrets/LLM_ROUTER_BEARER";
        };
      }
    ];

  rendered = (mkChainConfig { qwen = qwenChain; }).config.programs.litellmLocal.renderedConfig;
  fallbacks = rendered.litellm_settings.fallbacks;
  contextFallbacks = rendered.litellm_settings.context_window_fallbacks;

  chainFallbackPresent = lib.elem { "qwen-local" = [ "qwen-homelab" ]; } fallbacks;
  chainContextPresent = lib.elem { "qwen-local" = [ "qwen-homelab" ]; } contextFallbacks;

  # Every ladder keyed by a qwen-* rung, in either list. Non-empty, so the
  # "no terminal" claim below cannot pass by finding nothing to inspect.
  qwenLadders = lib.filter (e: lib.any (k: lib.hasPrefix "qwen-" k) (builtins.attrNames e)) (
    fallbacks ++ contextFallbacks
  );
  targetsOf = e: lib.concatLists (builtins.attrValues e);
  terminalNames = [
    "subagent"
    "subagent-homelab"
  ];
  noTerminalInQwenLadders =
    qwenLadders != [ ]
    && lib.all (e: lib.all (t: !(lib.elem t terminalNames)) (targetsOf e)) qwenLadders;

  qwenLocalEntry = lib.findFirst (d: d.model_name == "qwen-local") { } rendered.model_list;
  qwenLocalWindowDerived = (qwenLocalEntry.model_info.max_input_tokens or null) == 32768;
  qwenHomelabRouted = lib.any (
    d: d.model_name == "qwen-homelab" && d.litellm_params.model == "openai/qwen3.8-27b"
  ) rendered.model_list;

  # home-manager throws on ANY failed assertion once `config` is touched, so
  # catch it with tryEval rather than reading `config.assertions`.
  evaluates =
    chains:
    (builtins.tryEval (
      builtins.deepSeq (mkChainConfig chains).config.programs.litellmLocal.renderedConfig true
    )).success;
  plainChainAccepted = evaluates { qwen = qwenChain; };
  duplicateRungRejected =
    !(evaluates {
      qwen = qwenChain;
      other = [
        {
          name = "qwen-local";
          id = "test-local/other";
          contextWindow = 4096;
        }
      ];
    });
  cloudNamedRungRejected =
    !(evaluates {
      qwen = [
        {
          name = "qwen-openrouter";
          router = "qwen3.8-27b";
        }
      ];
    });
in
{
  litellm-local-isolated-chains =
    assert
      chainFallbackPresent
      || throw "isolatedChains.qwen must render the fallback {qwen-local = [qwen-homelab];}; got ${builtins.toJSON fallbacks}";
    assert
      chainContextPresent
      || throw "isolatedChains.qwen must render the context-window escape {qwen-local = [qwen-homelab];}, the next rung in the same chain; got ${builtins.toJSON contextFallbacks}";
    assert
      noTerminalInQwenLadders
      || throw "no qwen-* ladder may name the shared router's terminal rung (subagent / subagent-homelab): that is the cloud escape the chain exists to remove; got ${builtins.toJSON qwenLadders}";
    assert
      qwenLocalWindowDerived
      || throw "qwen-local declares no contextWindow, so it must inherit programs.mlx.modelContextWindows; without it the chain cannot escape an overflow; got ${builtins.toJSON qwenLocalEntry}";
    assert
      qwenHomelabRouted
      || throw "qwen-homelab must render as openai/qwen3.8-27b against the shared router, with no terminal rung appended";
    assert
      plainChainAccepted
      || throw "the qwen chain must evaluate: it is the positive control for the negative cases below";
    assert
      duplicateRungRejected
      || throw "a rung name repeated across two chains must fail the build: it would silently overwrite one ladder with the other";
    assert
      cloudNamedRungRejected
      || throw "an isolatedChains rung named for a cloud provider must fail the build: cloud policy belongs to the shared router alone";
    helpers.mkMarker "check-litellm-local-isolated-chains" "litellm-local: isolated chains fall through only to their own rungs, never the shared router terminal; duplicate and cloud-named rungs rejected";
}
