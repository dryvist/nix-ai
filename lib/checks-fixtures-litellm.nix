{ mkHmConfig }:
{
  # Evaluation with the local LiteLLM proxy enabled. The module is off by
  # default, so without this fixture every lib.optionalAttrs
  # litellmLocal.enable branch across the client modules would go unevaluated
  # and a typo in one of them would pass CI.
  hmConfigLitellmLocal = mkHmConfig [
    {
      programs = {
        litellmLocal = {
          enable = true;
          # Required once localModels is non-empty: the terminal rung forwards
          # the requested group name upstream, so it must name a group the shared
          # router serves rather than passing through the local rung's own name.
          routerEntryModel = "test-router-entry";
          # Local rungs are what give the subagent tier real depth: this host's own
          # models first, the shared router appended automatically as the terminal
          # rung. Declared here so the fallback-tier check asserts against the
          # shape a real host uses, not against an empty chain.
          localModels = [
            {
              # A ROUTER rung at the head: the estate's shape puts the shared
              # router's single-GPU group ahead of this host's own model.
              # Declared here so the fallback-tier check proves a router rung
              # renders against LLM_ROUTER_URL and carries no local window.
              name = "subagent";
              router = "test-gpu-group";
            }
            {
              name = "subagent-local";
              id = "test-local/small-4bit";
              contextWindow = 131072;
            }
            {
              # contextWindow OMITTED on purpose: this rung exercises the
              # derivation from mlx.modelContextWindows below. Without a rung
              # that leaves it null, the suite could only ever prove the
              # hand-written path and would pass unchanged if the derivation were
              # deleted.
              name = "subagent-local2";
              id = "test-local/tiny-4bit";
            }
          ];
        };
        # The catalog side of that derivation. Keyed by physical model id, the
        # same shape options-catalog.nix builds from real entries.
        mlx.modelContextWindows = {
          "test-local/tiny-4bit" = 32768;
        };
      };
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://llm.example.invalid/v1";
        llmEndpointTokenFile = "/run/secrets/LLM_ROUTER_BEARER";
      };
    }
  ];
}
