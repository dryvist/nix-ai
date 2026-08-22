# AI Stack — LLM Endpoint Selection
#
# Chooses which OpenAI-compatible endpoint the CLI consumers (cecli,
# qwen-code, fabric) target: the on-host llama-swap proxy (local-first
# default) or the cluster-hosted LiteLLM router. Split out of ./default.nix
# to keep each file under the repo file-size cap.
#
# The router carries the internal serving FQDN, so it is NEVER committed here
# as a literal — the consumer composes it from its own domain var and passes
# it in via `llmRouterEndpoint`. The bearer follows the HF_TOKEN pattern: only
# the token-file path is in the Nix store; the secret is read at exec time by
# a shell-init export.

{
  config,
  lib,
  ...
}:
let
  cfg = config.services.aiStack;
  registryAttrs = import ../../vars/ai-stack.nix;
in
{
  options.services.aiStack = {
    llmEndpoint = lib.mkOption {
      type = lib.types.enum (builtins.attrNames registryAttrs.endpoints ++ [ "router" ]);
      default = "mlx_local";
      description = ''
        Which well-known endpoint the OpenAI-compatible CLI consumers (cecli,
        qwen-code, fabric) target. `mlx_local` (default) keeps every consumer
        on the on-host llama-swap proxy — local-first. `router` points them at
        the cluster-hosted LiteLLM proxy given by `llmRouterEndpoint`; that
        path is bearer-gated, so `llmEndpointTokenFile` must also be set. The
        resolved URL is surfaced read-only as `resolvedLlmEndpoint`.
      '';
    };

    llmRouterEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "https://llm.<subdomain>/v1";
      description = ''
        Full OpenAI-compatible `/v1` base URL of the cluster-hosted LiteLLM
        router, injected by the consumer (never committed here — it carries
        the internal serving FQDN, which this public repo composes from a
        domain var on the consumer side, e.g. nix-darwin's baseDomain).

        Empty by default so this repo ships no personal endpoint. Required
        when `llmEndpoint = "router"`.
      '';
    };

    llmEndpointTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/LLM_ROUTER_BEARER";
      description = ''
        Path to a file holding the bearer token for the router endpoint. The
        token is read at exec time (shell init exports `OPENAI_API_KEY` from
        this path when `llmEndpoint != "mlx_local"`) and NEVER copied into the
        Nix store — only the path is committed, mirroring the HF_TOKEN /
        sops-rendered-file pattern. Unused (and unnecessary) when
        `llmEndpoint = "mlx_local"`; the loopback hop is unauthenticated.

        Leave null when the consumer already exports the bearer by another
        runtime path and sets `llmEndpointBearerFromEnv`.
      '';
    };

    llmEndpointBearerFromEnv = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Set when the consumer already exports `OPENAI_API_KEY` for the router
        by its own runtime mechanism (a keychain read at shell init, an agent
        sidecar, a credential helper) rather than through a token file. It
        satisfies the bearer requirement for `llmEndpoint = "router"` without
        this module owning a secret path.

        This exists because a consumer that provisions the bearer from a
        secret store has no file to point at, and inventing one would mean
        writing the secret to disk purely to satisfy an assertion — the
        opposite of what the token-file indirection is for.
      '';
    };

    resolvedLlmEndpoint = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default =
        registryAttrs.endpoints.${cfg.llmEndpoint}
          or (if cfg.llmEndpoint == "router" then cfg.llmRouterEndpoint else "");
      defaultText = lib.literalExpression "the endpoints.<llmEndpoint> URL (router → llmRouterEndpoint)";
      description = ''
        Read-only resolved OpenAI-compatible `/v1` base URL for the selected
        `llmEndpoint`. Consumers read this instead of hardcoding a URL.
      '';
    };

    isLocalLlmEndpoint = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = cfg.llmEndpoint == "mlx_local";
      defaultText = lib.literalExpression ''llmEndpoint == "mlx_local"'';
      description = ''
        Read-only: whether the selected endpoint is the unauthenticated
        on-host loopback hop. Consumers branch on this to decide whether a
        dummy API key suffices or a real bearer must be read from the
        environment. Read it instead of comparing `llmEndpoint` to the literal
        `"mlx_local"` — that string was spelled out in three separate consumer
        modules, so renaming the endpoint would have silently flipped each of
        them to the bearer-gated branch.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.llmEndpoint == "router" -> cfg.llmRouterEndpoint != "";
        message = "services.aiStack.llmEndpoint = \"router\" requires services.aiStack.llmRouterEndpoint (the consumer must supply the router /v1 base URL).";
      }
      {
        assertion =
          cfg.llmEndpoint == "router"
          -> (
            cfg.llmEndpointBearerFromEnv || (cfg.llmEndpointTokenFile != null && cfg.llmEndpointTokenFile != "")
          );
        message = "services.aiStack.llmEndpoint = \"router\" is bearer-gated: set services.aiStack.llmEndpointTokenFile to a non-empty path, or set services.aiStack.llmEndpointBearerFromEnv when the consumer already exports OPENAI_API_KEY itself.";
      }
      {
        assertion = !(cfg.llmEndpointBearerFromEnv && cfg.llmEndpointTokenFile != null);
        message = "services.aiStack.llmEndpointBearerFromEnv and services.aiStack.llmEndpointTokenFile are mutually exclusive — pick the one path that actually provisions the bearer.";
      }
    ];

    # Exec-time bearer: when a non-loopback endpoint is selected, export
    # OPENAI_API_KEY from the token file at shell init so the CLI consumers
    # (cecli, qwen-code, fabric) authenticate to the router. Only the path is
    # in the Nix store; the secret is read at runtime (HF_TOKEN pattern). The
    # loopback default sets nothing — its hop is unauthenticated.
    #
    # The `:-` guard makes this non-clobbering. Shell init order between
    # modules is not guaranteed, so an unconditional assignment here can run
    # after a consumer that provisions the same variable from its own secret
    # store and replace a good bearer with the empty string that `|| echo ""`
    # produces — a failure that surfaces as router 401s far from its cause.
    # Deferring to an already-set value also makes llmEndpointBearerFromEnv a
    # no-op here rather than a second competing writer.
    #
    # zsh only, deliberately: this repo's shell layer is zsh (see ai-shell.nix,
    # the only other shell-init here). The path is escapeShellArg'd, and the
    # empty-string guard keeps a misconfigured `""` from running `cat` with no
    # argument (which would block on stdin) — belt-and-suspenders with the
    # non-empty assertion above.
    programs.zsh.initContent =
      lib.mkIf
        (
          cfg.llmEndpoint != "mlx_local" && cfg.llmEndpointTokenFile != null && cfg.llmEndpointTokenFile != ""
        )
        (
          lib.mkAfter ''
            export OPENAI_API_KEY="''${OPENAI_API_KEY:-"$(cat ${lib.escapeShellArg cfg.llmEndpointTokenFile} 2>/dev/null || echo "")"}"
          ''
        );
  };
}
