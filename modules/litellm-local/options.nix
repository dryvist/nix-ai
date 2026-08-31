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

        `router` points subagents at the generated cost-ordered tier in
        ./fallback-tier.nix, which egresses to OpenRouter. That path is opt-in
        on purpose. Two constraints make it unsuitable as a default: every
        endpoint meeting the 512k floor AND a zero-data-retention policy is
        PAID (the free head the tier policy assumes does not exist at that
        window — verified against OpenRouter's /api/v1/endpoints/zdr), and a
        role that quietly bills turns a backend outage into spend nobody
        chose.
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

    tierRefresh = {
      enable = lib.mkEnableOption ''
        a periodic re-ranking of the subagent fallback tier against the live
        model catalog and the router's served set.

        The job only rewrites `tier-candidates.json` in a working copy; nothing
        reaches the running proxy until the next rebuild. That ordering is
        deliberate — the job proposes a re-ranking and logs whether the
        selection moved, and a human converges it. A timer that silently
        repointed live subagent traffic would reintroduce the failure the
        chain exists to remove: nobody notices the model changed
      '';

      checkout = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/Users/you/git/nix-ai";
        description = ''
          Absolute path to a working copy of this repository. The refresh
          rewrites `modules/litellm-local/tier-candidates.json` inside it.

          Required when `tierRefresh.enable` is set, and it must be a checkout
          rather than the Nix store path: the store copy is read-only, so a
          job pointed at it would fail at the last step, after both network
          fetches. The job fails loudly when this path does not exist.
        '';
      };

      interval = lib.mkOption {
        type = lib.types.ints.positive;
        default = 86400;
        description = ''
          Seconds between refreshes. Daily by default: two HTTP GETs is cheap,
          and it matches how fast the catalog actually moves — prices were
          observed drifting within a single day, and a model's availability
          within a week.
        '';
      };
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
