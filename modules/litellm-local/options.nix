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
      role and the role-to-model mapping changes upstream, with no change here
    '';

    port = lib.mkOption {
      type = lib.types.port;
      default = 4100;
      description = ''
        Loopback port for the proxy.

        Default 4100 avoids the ports already allocated by this repo's stack:
        8180 (fabric REST API), 11434 (llama-swap proxy), 11436 (vllm-mlx).
      '';
    };

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/litellm-local/master-key";
      defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/litellm-local/master-key"'';
      description = ''
        Path to the proxy's master key. Generated on activation when absent
        and never regenerated, so the value survives rebuilds; only the path
        is committed, mirroring `services.aiStack.llmEndpointTokenFile`.

        The proxy listens on loopback only, so this key is a guard against
        other local processes rather than a network credential. It is read at
        exec time by the launchd agent and exported at shell init for the
        clients — it is never written into the Nix store.
      '';
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:${toString cfg.port}/v1";
      defaultText = lib.literalExpression ''"http://127.0.0.1:''${port}/v1"'';
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
