# Local LiteLLM Proxy — Aggregator, Configuration, Runtime Wiring
#
# A loopback-only LiteLLM proxy that lets every CLI on this host name a stable
# *role* (`lead`, `subagent`, `judge`, `cheap`, ...) instead of a physical
# model id. Roles resolve upstream in the shared router, so changing which
# model a role means is an upstream edit, not a change to this repo.
#
# Two model groups, and the split between them is the whole point:
#
#   claude-*  ->  anthropic/claude-*  with the calling client's own credentials
#                 forwarded (no api_key here on purpose).
#   *         ->  the router named by services.aiStack.llmRouterEndpoint,
#                 authenticated with that endpoint's own bearer.
#
# Header forwarding is scoped to the `claude-*` group through
# `litellm_settings.model_group_settings.forward_client_headers_to_llm_api`,
# never the global `general_settings` boolean. A client credential must not
# reach the router leg, and the scoped list is what enforces that — the flake
# check `litellm-local-header-scope` asserts the list stays exactly `claude-*`.
#
# The proxy takes NO credential of its own (no `master_key`), deliberately:
#
# - A Claude Code session on a claude.ai subscription must send the gateway
#   no credential variable at all — any of them replaces the subscription
#   login (code.claude.com/docs/en/llm-gateway, "Subscriptions and gateways").
#   The only credential such a session can carry is its own OAuth bearer,
#   which belongs to Anthropic, not to this proxy.
# - Claude Code reaches this proxy from every surface — a login shell, the
#   desktop app, an IDE extension — and only `settings.json` reaches all of
#   them. `settings.json` is rendered into the Nix store, so nothing secret can
#   go through it. A proxy key therefore cannot reach every session, and a key
#   that reaches only some sessions breaks the rest (the 2026-08-24 outage:
#   every session without the key got `400 No connected db`).
# - The listener is loopback-only and the bearer it holds is already readable
#   by every process of the same user (`llmEndpointTokenFile` is that user's
#   file), so a key would not have guarded anything a local process could not
#   already read.
#
# One header still matters. LiteLLM forwards a client's OAuth `Authorization`
# upstream only when the request ALSO carries `x-litellm-api-key` — that is
# what tells it the Authorization header was not the proxy credential
# (litellm/proxy/litellm_pre_call_utils.py, add_headers_to_llm_call). With no
# master key its value is never checked, so the header is a constant routing
# marker (`clientToken`, "local"), not a secret, and it is rendered into
# `settings.json` like any other plain setting.
{
  config,
  pkgs,
  lib,
  userConfig,
  ...
}:
let
  cfg = config.programs.litellmLocal;
  aiStack = config.services.aiStack;
  versions = import ../../lib/versions.nix;

  # Fallback chain for the subagent tier: this host's own models first, the
  # shared router as the terminal rung. Its own file to stay under the
  # .file-size.yml ceiling; see that file for why no cloud model is named here.
  # Every local rung's serving window comes from the mlx catalog by default,
  # never from a number typed at the call site.
  # `programs.mlx.modelContextWindows` is already derived from the catalog entry
  # that decides what this host actually serves, so the window exists in exactly
  # one place. A second, hand-written copy would be free to disagree with the
  # server, and the direction it would disagree in is the dangerous one: an
  # OVER-declared window never trips the context-window escape, so an oversized
  # request is truncated locally instead of reaching the router -- precisely the
  # silent truncation the escape hatch exists to prevent. (The weights' own
  # `max_position_embeddings` is the wrong number for this: it states what the
  # architecture permits, not what this host's KV budget serves.)
  #
  # An id the catalog does not serve resolves to null and trips
  # fallback-tier.nix's contextWindow assertion. That is intended -- naming a
  # model this host does not serve is a build error, not a runtime 404.
  mlxWindows = config.programs.mlx.modelContextWindows or { };
  resolvedLocalModels = map (m: {
    inherit (m) name id;
    contextWindow = if m.contextWindow != null then m.contextWindow else mlxWindows.${m.id} or null;
  }) cfg.localModels;

  fallbackTier = import ./fallback-tier.nix {
    inherit lib;
    localModels = resolvedLocalModels;
    inherit (cfg) routerEntryModel;
  };

  # Reuses the maintainer profile's single traces endpoint rather than adding a
  # second one: this proxy's spans belong on the same path as Claude Code's and
  # Codex's, and one endpoint is one thing to keep correct. Null (the default,
  # and the only value a fresh consumer has) disables the callback entirely.
  #
  # `userConfig` is a MODULE ARGUMENT, not `config.userConfig`. Reading it off
  # `config` returns nothing and the `or null` swallows that into "telemetry is
  # off" — the config renders cleanly, the agent starts, and it exports nothing,
  # with no error anywhere. Same shape as the codex module, deliberately.
  telemetryEnabled =
    (userConfig.telemetry.enable or false) && (userConfig.telemetry.tracesEndpoint or null) != null;
  telemetryTracesEndpoint = if telemetryEnabled then userConfig.telemetry.tracesEndpoint else null;

  # LiteLLM's OTLP callback lives behind these three packages; litellm[proxy]
  # does not pull them. Same set the shared router installs, so the two agree.
  otelPackages = [
    "opentelemetry-api"
    "opentelemetry-sdk"
    "opentelemetry-exporter-otlp"
  ];

  # What the proxy serves, and how each group authenticates. Its own file; the
  # credential-forwarding scope that keeps a client bearer off the router leg
  # is documented there.
  proxyConfig = import ./proxy-config.nix {
    inherit lib fallbackTier telemetryTracesEndpoint;
  };

  configYaml = (pkgs.formats.yaml { }).generate "litellm-local-config.yaml" proxyConfig;

  # The launchd entry point plus the two operator commands.
  commands = import ./commands.nix {
    inherit
      pkgs
      lib
      aiStack
      cfg
      versions
      configYaml
      fallbackTier
      telemetryTracesEndpoint
      otelPackages
      ;
  };
  inherit (commands)
    fallbackProbe
    proxyScript
    ;

in
{
  imports = [ ./options.nix ];

  config = lib.mkMerge [
    # Set unconditionally so a flake check can read the rendered config (and
    # assert on the forwarding scope) without enabling the launchd agent —
    # the same introspection pattern as programs.codex.mcpServerNames.
    { programs.litellmLocal.renderedConfig = proxyConfig; }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = aiStack.llmEndpoint == "router";
          message = "programs.litellmLocal.enable requires services.aiStack.llmEndpoint = \"router\": the proxy's non-Anthropic model group forwards to services.aiStack.llmRouterEndpoint, which only the router endpoint provides.";
        }
        {
          assertion = aiStack.llmEndpointTokenFile != null && aiStack.llmEndpointTokenFile != "";
          message = "programs.litellmLocal.enable requires services.aiStack.llmEndpointTokenFile: the proxy runs as a launchd agent, which has no shell init, so services.aiStack.llmEndpointBearerFromEnv cannot reach it. Point llmEndpointTokenFile at the file holding the router bearer.";
        }
      ]
      ++ fallbackTier.assertions;

      home.packages = [ fallbackProbe ];

      launchd.agents = import ./launchd.nix {
        inherit
          config
          lib
          cfg
          aiStack
          proxyScript
          telemetryTracesEndpoint
          ;
      };

      # Client-side environment for the OpenAI-compatible CLIs.
      #
      # mkBefore, deliberately: endpoint.nix appends a `:-` guarded
      # OPENAI_API_KEY export that defers to an already-set value, so running
      # first makes this the winner. With the proxy enabled no interactive
      # client talks to the router directly, so none of them needs the router
      # bearer; the proxy checks no credential, but OpenAI-compatible SDKs
      # refuse an empty key, so every client sends the same placeholder. The
      # router bearer stays confined to the launchd agent's own environment.
      #
      # LLM_ROUTER_URL and LLM_ROUTER_TOKEN_FILE are exported for callers that
      # must reach the UPSTREAM router directly rather than through this proxy
      # — asking what a role actually resolves to, which the local `*` wildcard
      # hides. Both values are non-secret (an address and a path); the token
      # file's CONTENTS are never exported, so a caller reads the file itself
      # at the moment it needs the bearer. Claude Code gets the same three
      # non-secret values through settings.json (modules/claude/settings-env.nix)
      # so its hooks see them from every surface, not only a login shell.
      programs.zsh.initContent = lib.mkBefore (
        ''
          export LITELLM_LOCAL_KEY=${lib.escapeShellArg cfg.clientToken}
          export OPENAI_API_KEY="$LITELLM_LOCAL_KEY"
          export LLM_ROUTER_URL=${lib.escapeShellArg aiStack.llmRouterEndpoint}
          export LLM_ROUTER_TOKEN_FILE=${lib.escapeShellArg (toString aiStack.llmEndpointTokenFile)}
        ''
        + lib.optionalString (aiStack.internalDomains != [ ]) ''
          export CLAUDE_SUBAGENT_INTERNAL_DOMAINS=${lib.escapeShellArg (lib.concatStringsSep " " aiStack.internalDomains)}
        ''
      );
    })
  ];
}
