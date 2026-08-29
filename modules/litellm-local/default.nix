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

  # Cost-ordered fallback chain for the subagent tier. Its own file to stay
  # under the .file-size.yml ceiling; see that file for why a chain replaced a
  # single pinned model.
  fallbackTier = import ./fallback-tier.nix { inherit lib; };

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

  # `os.environ/NAME` is LiteLLM's own indirection: the literal string is what
  # goes in the config file, and LiteLLM resolves it from the process
  # environment at load time. That is what keeps the router bearer out of the
  # store.
  proxyConfig = {
    model_list = [
      {
        model_name = "claude-*";
        # No api_key, deliberately: this deployment is reached with the OAuth
        # bearer the calling client already holds, forwarded by the scoped rule
        # below. An api_key here would override that bearer and bill the wrong
        # account.
        #
        # LiteLLM only treats a client bearer as forwardable OAuth when it
        # carries the `sk-ant-oat` prefix (see its anthropic common_utils
        # optionally_handle_anthropic_oauth). A client sending any other token
        # shape therefore gets no credential on this leg rather than the wrong
        # one — the failure is a 401, not a silent mis-auth.
        #
        # `anthropic/claude-*`, not `anthropic/*`: the wildcard substitutes only
        # the part the pattern matched, so `anthropic/*` turned a request for
        # `claude-opus-5` into an upstream request for `opus-5`, which Anthropic
        # rejects as an unknown model.
        litellm_params.model = "anthropic/claude-*";
      }
      {
        model_name = "*";
        litellm_params = {
          model = "openai/*";
          api_base = "os.environ/LLM_ROUTER_URL";
          api_key = "os.environ/OPENAI_API_KEY";
        };
      }
    ]
    # Named tier groups come after the wildcards deliberately: an explicit
    # model_name always wins over `*`, so ordering here is documentation, not
    # routing. Naming them at all is the point — `*` would resolve
    # `subagent-free` upstream, where the alias may not exist.
    ++ fallbackTier.modelList;

    litellm_settings = {
      # Clients disagree about which sampling params they send; dropping the
      # ones a given backend rejects keeps a role swap from breaking a client.
      drop_params = true;
      model_group_settings.forward_client_headers_to_llm_api = [ "claude-*" ];

      # Retry a transient upstream failure before declaring the group down.
      # This is the cheap half of "never let it die": most 5xx and connection
      # resets clear on a retry, and only a persistent failure should spend a
      # fallback.
      num_retries = 3;

      # The cost-ordered chain. `[{group: [fallback, ...]}]` is LiteLLM's own
      # shape (proxy_server_config.yaml), and the same shape the upstream
      # router already reports back in its error payloads.
      #
      # Scoped to the tier groups on purpose — there is deliberately NO
      # `default_fallbacks` here. A blanket default would also catch
      # `claude-*`, silently answering a main session from a free model when
      # Anthropic rate-limits. Losing the request is recoverable; not noticing
      # the model changed underneath a long session is not. The main tier gets
      # retries and a context-window fallback, never a silent quality swap.
      fallbacks = fallbackTier.fallbacks;

      # A context-window overflow is unambiguous — the request cannot succeed
      # as sent, and a larger window is strictly better rather than a
      # downgrade. That makes it the one case where routing the main tier
      # elsewhere is safe.
      # Target is the tier's OWN entry point, never a literal: the head group
      # is named once in fallback-tier.nix and a refresh reorders what sits
      # behind it. A hardcoded name here ("subagent-cheap") was not an emitted
      # model_list group at all, so it failed the explicit-group check.
      context_window_fallbacks = [ { "claude-*" = [ fallbackTier.entryPoint ]; } ];
    }
    # Every non-Anthropic call this host makes traverses this proxy, so with no
    # callback the entire local fabric is an observability blind spot.
    #
    # `otel`, NOT `langfuse` — a deliberate match with the shared router rather
    # than a second mechanism. LiteLLM's `langfuse` callback needs the v2 SDK
    # and errors on init against the v3 that pip resolves today; the collector
    # already fans traces out to Langfuse, so one emitter on one path reaches
    # the same sink with nothing extra to keep in step. It also means this
    # proxy needs no Langfuse credential of its own.
    #
    # Only ever set when there is somewhere to send them: an OTLP exporter with
    # no endpoint falls back to a conventional loopback address and exports
    # into a black hole, which is exactly the failure this repo already fixed
    # once for Claude Code. No endpoint, no callback.
    // lib.optionalAttrs (telemetryTracesEndpoint != null) { callbacks = [ "otel" ]; };
  };

  configYaml = (pkgs.formats.yaml { }).generate "litellm-local-config.yaml" proxyConfig;

  # The proxy runs from a uvx environment pinned to the Renovate-tracked release
  # in lib/versions.nix, the same way the MLX stack does, rather than from
  # nixpkgs' litellm: nixpkgs lags the upstream release train by months, and
  # building it from source drags a large Python test closure (the rq test
  # suite among it) into every CI and workstation rebuild.
  uvPythonVersion = (import ../../lib/python.nix { inherit pkgs; }).pythonVersion;

  # Liveness probe for the fallback chain. The chain's members are named here
  # so the command needs no arguments in the common case — running it bare
  # checks exactly what this host is configured to fall back through.
  fallbackProbe = pkgs.writeShellApplication {
    name = "litellm-fallback-probe";
    runtimeInputs = [
      pkgs.curl
      pkgs.python3
    ];
    # The chain is passed as an environment variable, not as default
    # arguments: `"''${@:-a b c}"` collapses the default into ONE argument, so
    # the probe asked for a model literally named "a b c" and got a 404 that
    # looked like a dead chain. Word-splitting the default belongs in the
    # script, which is also where the no-inline-shell rule wants it.
    text = ''
      LITELLM_FALLBACK_CHAIN=${lib.escapeShellArg (lib.concatStringsSep " " fallbackTier.names)} \
        exec ${./../scripts/litellm-fallback-probe.sh} "$@"
    '';
  };

  # Regenerates ./tier-candidates.json from the live catalog. It writes into a
  # CHECKOUT, not the store, so the candidates path is a required argument
  # rather than baked in — a wrapper pointing at the read-only store copy would
  # fail at the last step, after both network fetches.
  tierRefresh = pkgs.writeShellApplication {
    name = "litellm-tier-refresh";
    runtimeInputs = [
      pkgs.curl
      pkgs.python3
    ];
    text = ''
      exec ${./../scripts/litellm-tier-refresh.sh} "$@"
    '';
  };

  # launchd agents get no shell init, so the wrapper reads the router bearer
  # from its file itself. This is also why the assertion below requires
  # llmEndpointTokenFile: llmEndpointBearerFromEnv provisions the bearer into
  # an interactive shell, which this agent never has.
  proxyScript = pkgs.writeShellScript "litellm-local-start" ''
    set -euo pipefail
    OPENAI_API_KEY="$(cat ${lib.escapeShellArg (toString aiStack.llmEndpointTokenFile)})"
    export OPENAI_API_KEY
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} \
      --from "litellm[proxy]==${versions.litellm}" \
      ${
        lib.concatMapStringsSep " " (p: "--with ${lib.escapeShellArg p}") (
          lib.optionals (telemetryTracesEndpoint != null) otelPackages
        )
      } litellm \
      --config ${configYaml} \
      --host 127.0.0.1 \
      --port ${toString cfg.port}
  '';
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

      home.packages = [
        fallbackProbe
        tierRefresh
      ];

      launchd.agents.litellm-local = {
        enable = true;
        config = {
          Label = "dev.litellm-local";
          ProgramArguments = [ "${proxyScript}" ];
          RunAtLoad = true;
          KeepAlive = true;
          # Throttle restarts so a bad config or an unreadable secret file
          # fails visibly in the log instead of spinning.
          ThrottleInterval = 30;
          ProcessType = "Background";
          EnvironmentVariables = {
            # Not a secret — the router URL is a plain address, so it needs no
            # exec-time file read.
            LLM_ROUTER_URL = aiStack.llmRouterEndpoint;
            HOME = config.home.homeDirectory;
          }
          # LiteLLM reads its OWN names here — `OTEL_EXPORTER` / `OTEL_ENDPOINT`
          # — not the standard OTEL_EXPORTER_OTLP_* pair. Setting the standard
          # names instead leaves the callback pointed at its loopback default
          # and exporting nowhere, with no error. Endpoint carries the full
          # signal path because LiteLLM posts it verbatim.
          // lib.optionalAttrs (telemetryTracesEndpoint != null) {
            OTEL_EXPORTER = "otlp_http";
            OTEL_ENDPOINT = telemetryTracesEndpoint;
          };
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/litellm-local/litellm-local.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/litellm-local/litellm-local.error.log";
        };
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
