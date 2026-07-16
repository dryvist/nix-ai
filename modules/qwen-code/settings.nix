#
# Qwen Code Module — Settings Generation
#
# Writes ~/.qwen/settings.json. Schema documented at
# https://github.com/QwenLM/qwen-code (look for the configuration table).
# Key blocks:
#   - modelProviders[]    Each provider declares baseUrl, protocol, model
#                         list, and the env var that holds the API key.
#   - env                 Fallback API-key store (lowest priority; we
#                         leave empty and prefer .env files for secrets).
#   - security.auth       The active provider type (openai for our local
#                         llama-swap routing).
#   - model.name          Default model on startup.
#
# We declare a single `mlx-local-llama-swap` provider that points at the
# local llama-swap and lists every capability-class alias from the
# registry. Users can layer additional providers via
# programs.qwen-code.extraSettings.modelProviders.
#
{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.programs.qwen-code;
  homeDir = config.home.homeDirectory;
  inherit (config.services.aiStack) models resolvedLlmEndpoint llmEndpoint;

  mcpClient = import ../mcp/client.nix { inherit lib; };

  # Endpoint + API-key source both follow services.aiStack.llmEndpoint. Local
  # (llama-swap) is an open loopback hop, so a dummy key satisfies the schema.
  # The router is bearer-gated: point qwen-code's envKey at OPENAI_API_KEY,
  # which ai-stack exports at shell init from llmEndpointTokenFile (never in
  # the Nix store), and drop the literal so the real token is read from env.
  endpointBase = resolvedLlmEndpoint;
  isLocalEndpoint = llmEndpoint == "mlx_local";
  apiKeyEnvVar = if isLocalEndpoint then "QWEN_LOCAL_DUMMY_KEY" else "OPENAI_API_KEY";
  providerKey = "mlx-local-llama-swap";

  # llama-swap routes capability-class aliases (default, coding, ...). The
  # qwen-code model schema only accepts `name` and `description` — routing
  # is implicit in the provider's baseUrl, not a per-model field.
  modelEntries = lib.mapAttrsToList (role: physical: {
    name = role;
    description = "${role} → ${physical} via llama-swap";
  }) models;

  defaultModelName = cfg.model;

  normalizeMcpServer =
    server:
    if server.url != null then
      lib.filterAttrs (_name: value: value != null && value != [ ] && value != { }) (
        {
          inherit (server) headers timeout;
        }
        // (if server.type == "sse" then { inherit (server) url; } else { httpUrl = server.url; })
      )
    else
      lib.filterAttrs (_name: value: value != null && value != [ ] && value != { }) {
        inherit (server)
          command
          args
          env
          cwd
          timeout
          ;
      };

  mcpServers = mcpClient.renderServers {
    inherit (config.programs.aiMcp) enabledServers;
    excluded = cfg.excludedMcpServers;
    normalize = normalizeMcpServer;
  };

  baseSettings = {
    inherit mcpServers;

    modelProviders = [
      {
        name = providerKey;
        protocol = "openai";
        baseUrl = endpointBase;
        # Local: envKey points at a name only set to the "dummy" literal
        # below (llama-swap's local hop is open). Router: envKey is
        # OPENAI_API_KEY, left out of the env block so qwen-code reads the
        # real bearer from the process environment.
        envKey = apiKeyEnvVar;
        models = modelEntries;
      }
    ];

    env = lib.optionalAttrs isLocalEndpoint {
      QWEN_LOCAL_DUMMY_KEY = "dummy";
    };

    security.auth.selectedType = "openai";

    model.name = defaultModelName;
  };

  # Deep merge user extras over our base. recursiveUpdate replaces leaf
  # values, including lists — so modelProviders gets special handling:
  # base providers stay, user providers append. Everything else
  # (env entries, security, model.name) deep-merges normally.
  extraProviders = cfg.extraSettings.modelProviders or [ ];
  extraWithoutProviders = builtins.removeAttrs cfg.extraSettings [ "modelProviders" ];
  finalSettings = (lib.recursiveUpdate baseSettings extraWithoutProviders) // {
    modelProviders = baseSettings.modelProviders ++ extraProviders;
  };

  settingsJson = pkgs.writeText "qwen-settings.json" (builtins.toJSON finalSettings);
in
{
  config = lib.mkMerge [
    {
      programs.qwen-code.mcpServerNames = lib.attrNames mcpServers;
    }
    (lib.mkIf cfg.enable {
      home = {
        activation.qwenCodeSettingsMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          export PATH="${pkgs.jq}/bin:$PATH"
          $DRY_RUN_CMD ${../scripts/merge-json-settings.sh} \
            "${settingsJson}" \
            "${homeDir}/.qwen/settings.json"
        '';

        # History dir keep-file; qwen-code writes session state here.
        file.".qwen/.history-keep" = {
          target = ".qwen/history/.keep";
          text = "# Managed by Nix - programs.qwen-code\n";
        };
      };
    })
  ];
}
