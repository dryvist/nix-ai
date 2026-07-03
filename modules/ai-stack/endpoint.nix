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
  };

  config = {
    assertions = [
      {
        assertion = cfg.llmEndpoint == "router" -> cfg.llmRouterEndpoint != "";
        message = "services.aiStack.llmEndpoint = \"router\" requires services.aiStack.llmRouterEndpoint (the consumer must supply the router /v1 base URL).";
      }
      {
        assertion =
          cfg.llmEndpoint == "router" -> (cfg.llmEndpointTokenFile != null && cfg.llmEndpointTokenFile != "");
        message = "services.aiStack.llmEndpoint = \"router\" requires services.aiStack.llmEndpointTokenFile to be a non-empty path to the bearer token file.";
      }
    ];

    # Exec-time bearer: when a non-loopback endpoint is selected, export
    # OPENAI_API_KEY from the token file at shell init so the CLI consumers
    # (cecli, qwen-code, fabric) authenticate to the router. Only the path is
    # in the Nix store; the secret is read at runtime (HF_TOKEN pattern). The
    # loopback default sets nothing — its hop is unauthenticated.
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
            export OPENAI_API_KEY="$(cat ${lib.escapeShellArg cfg.llmEndpointTokenFile} 2>/dev/null || echo "")"
          ''
        );
  };
}
