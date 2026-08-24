# Local LiteLLM Proxy — Aggregator, Configuration, Runtime Wiring
#
# A loopback-only LiteLLM proxy that lets every CLI on this host name a stable
# *role* (`lead`, `subagent`, `judge`, `cheap`, ...) instead of a physical
# model id. Roles resolve upstream in the shared router, so changing which
# model a role means is an upstream edit, not a change to this repo.
#
# Two model groups, and the split between them is the whole point:
#
#   claude-*  ->  anthropic/*  with the calling client's own credentials
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
# Secrets: the router bearer and the proxy's own master key are read from
# files at exec time by the launchd wrapper, and exported at shell init for
# the clients. Neither value is ever written into the Nix store.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.litellmLocal;
  aiStack = config.services.aiStack;

  # `os.environ/NAME` is LiteLLM's own indirection: the literal string is what
  # goes in the config file, and LiteLLM resolves it from the process
  # environment at load time. That is what keeps every secret out of the store.
  proxyConfig = {
    model_list = [
      {
        model_name = "claude-*";
        # No api_key: this deployment is reached with the credentials the
        # calling client already holds, forwarded by the scoped rule below.
        litellm_params.model = "anthropic/*";
      }
      {
        model_name = "*";
        litellm_params = {
          model = "openai/*";
          api_base = "os.environ/LLM_ROUTER_URL";
          api_key = "os.environ/OPENAI_API_KEY";
        };
      }
    ];

    litellm_settings = {
      # Clients disagree about which sampling params they send; dropping the
      # ones a given backend rejects keeps a role swap from breaking a client.
      drop_params = true;
      model_group_settings.forward_client_headers_to_llm_api = [ "claude-*" ];
    };

    general_settings.master_key = "os.environ/LITELLM_LOCAL_KEY";
  };

  configYaml = (pkgs.formats.yaml { }).generate "litellm-local-config.yaml" proxyConfig;

  litellmPkg = pkgs.litellm;

  # launchd agents get no shell init, so the wrapper reads both secrets from
  # their files itself. This is also why the assertion below requires
  # llmEndpointTokenFile: llmEndpointBearerFromEnv provisions the bearer into
  # an interactive shell, which this agent never has.
  proxyScript = pkgs.writeShellScript "litellm-local-start" ''
    set -euo pipefail
    OPENAI_API_KEY="$(cat ${lib.escapeShellArg (toString aiStack.llmEndpointTokenFile)})"
    LITELLM_LOCAL_KEY="$(cat ${lib.escapeShellArg cfg.keyFile})"
    export OPENAI_API_KEY LITELLM_LOCAL_KEY
    exec ${lib.getExe' litellmPkg "litellm"} \
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
      ];

      # Generate the master key once, on first activation. Regenerating it on
      # every rebuild would invalidate the header every already-running client
      # is sending, so the guard is `absent`, not `stale`.
      home.activation.litellmLocalKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -s ${lib.escapeShellArg cfg.keyFile} ]; then
          $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg (builtins.dirOf cfg.keyFile)}
          $DRY_RUN_CMD ${lib.getExe' pkgs.openssl "openssl"} rand -hex 32 \
            > ${lib.escapeShellArg cfg.keyFile}
          $DRY_RUN_CMD chmod 600 ${lib.escapeShellArg cfg.keyFile}
        fi
      '';

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
          };
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/litellm-local/litellm-local.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/litellm-local/litellm-local.error.log";
        };
      };

      # Exec-time client credentials, mirroring ai-stack/endpoint.nix.
      #
      # mkBefore, deliberately: endpoint.nix appends a `:-` guarded
      # OPENAI_API_KEY export that defers to an already-set value, so running
      # first makes this the winner. That is the correct precedence — with the
      # proxy enabled, no interactive client talks to the router directly, so
      # the bearer they need is this proxy's key, not the router's. The router
      # bearer stays confined to the launchd agent's own environment.
      #
      # ANTHROPIC_CUSTOM_HEADERS lives here rather than in Claude Code's
      # settings.json because settings.json values are literals: rendering the
      # key there would copy it into the Nix store.
      programs.zsh.initContent = lib.mkBefore ''
        LITELLM_LOCAL_KEY="$(cat ${lib.escapeShellArg cfg.keyFile} 2>/dev/null || echo "")"
        export LITELLM_LOCAL_KEY
        export OPENAI_API_KEY="$LITELLM_LOCAL_KEY"
        export ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $LITELLM_LOCAL_KEY"
      '';
    })
  ];
}
