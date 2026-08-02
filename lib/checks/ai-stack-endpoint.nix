# services.aiStack endpoint regression tests
#
# The router endpoint is bearer-gated, and the two ways to satisfy that gate
# (a token file, or a bearer the consumer already exports) must both keep
# working. These evaluate the endpoint module directly against a minimal stub
# of the one home-manager option it writes, so the assertions and the rendered
# shell init are exercised without pulling in home-manager.
{ pkgs }:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };

  # Minimal stand-ins for what endpoint.nix writes but does not declare:
  # home-manager's zsh init option, and the assertions list the module system
  # only provides inside NixOS/home-manager evaluations.
  hostStub = {
    options = {
      programs.zsh.initContent = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      assertions = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              assertion = lib.mkOption { type = lib.types.bool; };
              message = lib.mkOption { type = lib.types.str; };
            };
          }
        );
        default = [ ];
      };
    };
  };

  evalEndpoint =
    settings:
    (lib.evalModules {
      modules = [
        hostStub
        ../../modules/ai-stack/endpoint.nix
        { services.aiStack = settings; }
      ];
    }).config;

  # An assertion only fires when something forces it, so force them explicitly
  # and report whether the configuration was accepted.
  accepts =
    settings:
    let
      c = evalEndpoint settings;
      failures = builtins.filter (a: !a.assertion) c.assertions;
    in
    (builtins.tryEval (builtins.deepSeq c.services.aiStack.resolvedLlmEndpoint failures)).success
    && failures == [ ];

  routerUrl = "https://llm.example.invalid/v1";

  # mlx_local is the local-first default and must need no bearer at all.
  localDefaultOk = accepts { };

  bearerFromEnvOk = accepts {
    llmEndpoint = "router";
    llmRouterEndpoint = routerUrl;
    llmEndpointBearerFromEnv = true;
  };

  tokenFileOk = accepts {
    llmEndpoint = "router";
    llmRouterEndpoint = routerUrl;
    llmEndpointTokenFile = "/run/secrets/LLM_ROUTER_BEARER";
  };

  # Router with no bearer at all must be rejected, not silently unauthenticated.
  ungatedRejected =
    !accepts {
      llmEndpoint = "router";
      llmRouterEndpoint = routerUrl;
    };

  # Two competing bearer sources must be rejected rather than one silently winning.
  bothRejected =
    !accepts {
      llmEndpoint = "router";
      llmRouterEndpoint = routerUrl;
      llmEndpointBearerFromEnv = true;
      llmEndpointTokenFile = "/run/secrets/LLM_ROUTER_BEARER";
    };

  # The token-file export must defer to an already-set value: shell-init order
  # between modules is not guaranteed, and an unconditional assignment can
  # replace a consumer-provided bearer with an empty string.
  tokenFileInit =
    (evalEndpoint {
      llmEndpoint = "router";
      llmRouterEndpoint = routerUrl;
      llmEndpointTokenFile = "/run/secrets/LLM_ROUTER_BEARER";
    }).programs.zsh.initContent;

  initIsNonClobbering = lib.hasInfix ''OPENAI_API_KEY="''${OPENAI_API_KEY:-'' tokenFileInit;
in
{
  ai-stack-endpoint-bearer-gate =
    assert
      localDefaultOk || throw "services.aiStack default (mlx_local) must evaluate without a bearer";
    assert bearerFromEnvOk || throw "llmEndpoint=router with llmEndpointBearerFromEnv must be accepted";
    assert tokenFileOk || throw "llmEndpoint=router with llmEndpointTokenFile must be accepted";
    assert ungatedRejected || throw "llmEndpoint=router with no bearer must be rejected";
    assert bothRejected || throw "llmEndpoint=router with both bearer sources must be rejected";
    helpers.mkMarker "check-ai-stack-endpoint-bearer-gate" "services.aiStack router endpoint: bearer gate accepts a token file or an externally exported bearer, and rejects neither-or-both";

  ai-stack-endpoint-init-non-clobbering =
    assert
      initIsNonClobbering
      || throw "the router bearer export must defer to an already-set OPENAI_API_KEY; got: ${tokenFileInit}";
    helpers.mkMarker "check-ai-stack-endpoint-init-non-clobbering" "services.aiStack router bearer export defers to an already-set OPENAI_API_KEY";
}
