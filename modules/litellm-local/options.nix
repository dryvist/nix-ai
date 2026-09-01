# Local LiteLLM Proxy — Option Declarations
#
# All `options.programs.litellmLocal` declarations live here, mirroring the
# per-module options.nix split used by fabric and the other agent modules.
{ config, lib, ... }:
let
  cfg = config.programs.litellmLocal;
in
{
  options.programs.litellmLocal = {
    enable = lib.mkEnableOption ''
      a loopback-only LiteLLM proxy in front of the shared router.

      It serves two model groups: `claude-*` deployments reach Anthropic
      directly with the calling client's own credentials forwarded, and every
      other model name is a role alias proxied to the router named by
      `services.aiStack.llmRouterEndpoint`. Clients therefore name a stable
      role and the role-to-model mapping changes upstream, with no change here.

      The proxy checks no credential of its own — it is loopback-only, and a
      subscription Claude Code session cannot send a gateway credential
      without losing the subscription (see the module header)
    '';

    subagentTier = lib.mkOption {
      type = lib.types.enum [
        "anthropic"
        "router"
      ];
      default = "anthropic";
      description = ''
        Which tier Claude Code's subagents run on.

        `anthropic` (default) pins `CLAUDE_CODE_SUBAGENT_MODEL` to an explicit
        `claude-*` id, so a subagent is a NATIVE Claude subagent: the request
        matches the `claude-*` group, reaches Anthropic with the caller's own
        forwarded credential, and never touches the router leg. No third-party
        egress, so no data-retention question to answer.

        `router` points subagents at the tier in ./fallback-tier.nix: this
        host's own models first, then the shared router as the terminal rung.
        That path is opt-in on purpose. A local rung serves at no cost, but a
        request that overflows its window escapes to the terminal rung, and
        what the router does behind that — including whether it bills — is
        configured there rather than here.
      '';
    };

    claudeDirect = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Take the proxy out of Claude Code's path entirely.

        When true, `ANTHROPIC_BASE_URL` and `ANTHROPIC_CUSTOM_HEADERS` are not
        emitted at all, so Claude Code talks straight to Anthropic with no
        LiteLLM hop, no wildcard group, and nothing that can reroute a
        Claude-shaped model name. The proxy keeps running for the OpenAI-shaped
        clients that need it; only Claude Code stops using it.

        This is the panic switch for "no routing or impact at all". The cost is
        observability: Claude Code traffic no longer passes the proxy, so the
        `otel` callback there sees none of it (Claude Code's own OTEL export is
        unaffected).
      '';
    };

    subagentAnthropicModel = lib.mkOption {
      type = lib.types.str;
      default = "claude-sonnet-5[1m]";
      description = ''
        The model id `subagentTier = "anthropic"` pins subagents to.

        Must be a full `claude-*` id carrying the `[1m]` suffix. Both halves
        matter. A bare capability alias (`sonnet`, or `sonnet[1m]`) does NOT
        match the proxy's `claude-*` group, so it falls through the `*`
        wildcard to the router and egresses to a third party — the exact leak
        `claudeShapedNamesCannotReachWildcard` in
        lib/checks/litellm-local.nix now rejects. The `[1m]` suffix is
        required because a subagent here is expected to carry a context no
        200k window can hold.
      '';
    };

    localModels = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Group name clients address. The FIRST entry must be `subagent` — consumers name that string forever.";
            };
            id = lib.mkOption {
              type = lib.types.str;
              description = "Model id as this host's own server serves it.";
            };
            contextWindow = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.positive;
              default = null;
              description = ''
                Real serving window in tokens -- what lets LiteLLM detect an
                overflow and escape to the shared router instead of letting the
                model truncate silently.

                Null (the default) DERIVES it from `programs.mlx.modelContextWindows`,
                which the mlx catalog already computes for the model this host
                serves. Leave it null: the catalog is the single source, and a
                number written here is free to drift above the real window,
                which silently disables the escape.

                Set it only for a model served by something other than the mlx
                catalog. An id the catalog does not serve and that carries no
                explicit value fails the build.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        Models THIS host serves itself, tried before the shared router.

        Ordered: LiteLLM walks the list as written. The shared homelab router is
        appended automatically as the final rung, so the chain always ends
        somewhere with the router's own fallbacks behind it.

        Empty (the default) preserves the previous behaviour — everything goes
        straight to the router.

        Never name a cloud provider here. The router already owns a
        credentialed, budgeted, ordered cloud chain; naming one here puts the
        decision in two places, and `fallback-tier.nix` asserts against it.
      '';
    };

    localEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434/v1";
      description = ''
        OpenAI-compatible base URL for this host's own model server. Loopback by
        default — the point of the local rungs is that they keep working when
        the network or the shared router does not.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4100;
      description = ''
        Loopback port for the proxy.

        Default 4100 avoids the ports already allocated by this repo's stack:
        8180 (fabric REST API), 11434 (llama-swap proxy), 11436 (vllm-mlx).
      '';
    };

    clientToken = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "local";
      description = ''
        The placeholder every client sends the proxy as its API key. Not a
        secret: the proxy checks no credential (see the module header for
        why it cannot). It exists because OpenAI-compatible SDKs refuse an
        empty key, and because LiteLLM forwards a client's own OAuth bearer
        upstream only when the request also carries `x-litellm-api-key` —
        Claude Code sends this value in that header for exactly that reason.
      '';
    };

    rootUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:${toString cfg.port}";
      defaultText = lib.literalExpression ''"http://127.0.0.1:''${port}"'';
      description = ''
        Read-only root URL of the local proxy, with no API prefix. Clients
        that append their own prefix read this: Claude Code appends the
        Anthropic paths, and a Gemini-format client appends
        `/v1beta/models/<model>:generateContent`. Clients wanting the
        OpenAI-compatible base read `baseUrl` instead.
      '';
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${cfg.rootUrl}/v1";
      defaultText = lib.literalExpression ''"''${rootUrl}/v1"'';
      description = ''
        Read-only OpenAI-compatible `/v1` base URL of the local proxy. The
        CLI consumers read this instead of composing the loopback URL
        themselves, so the port is declared once.
      '';
    };

    renderedConfig = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = ''
        The proxy configuration as an attrset, before YAML serialization.
        Exists so a flake check can assert on it without parsing YAML —
        specifically that client-header forwarding stays scoped to the
        `claude-*` group and never reaches the router deployment.
      '';
    };
  };
}
