#
# Qwen Code Module — Settings Generation
#
# Writes ~/.qwen/settings.json. Schema documented at
# https://github.com/QwenLM/qwen-code (look for the configuration table).
# Key blocks:
#   - modelProviders      `{ <authType> = [ model ]; }`, rendered from the
#                         provider list below (baseUrl, protocol, models,
#                         API-key env var) at write time.
#   - env                 Fallback API-key store (lowest priority; router
#                         providers use the process environment).
#   - security.auth       The active provider type (openai for our local
#                         llama-swap routing).
#   - model.name          Default model on startup.
#
# A host with a static Qwen resident gets a provider for its catalog keys.
# Other hosts use the `mlx-local-llama-swap` provider and its role names or
# router capability aliases. Users can layer providers via
# programs.qwen-code.extraSettings.modelProviders.
#
{
  pkgs,
  config,
  lib,
  nix-claude-code,
  ...
}:

let
  cfg = config.programs.qwen-code;
  homeDir = config.home.homeDirectory;
  modelMode = import ./model-mode.nix { inherit config lib; };
  inherit (config.services.aiStack) llmEndpoint;

  aiCommon = import ../common {
    inherit lib config nix-claude-code;
  };
  inherit (aiCommon) permissions formatters;
  formattedPermissions = formatters.qwen.formatPermissions permissions;
  qwenPermissions = formattedPermissions // {
    deny =
      formattedPermissions.deny
      ++ lib.unique (lib.filter (tool: !(builtins.elem tool formattedPermissions.deny)) cfg.excludeTools);
  };

  mcpClient = import ../mcp/client.nix { inherit lib; };

  # Endpoint + API-key source both follow services.aiStack.llmEndpoint. Local
  # (llama-swap) is an open loopback hop, so a dummy key satisfies the schema.
  # Both the bearer-gated router and litellm-local expose OPENAI_API_KEY to the
  # client process; the sandbox forwards only that key and the optional base URL.
  inherit (config.programs) litellmLocal;
  endpointBase = import ./endpoint.nix { inherit config; };
  isLocalEndpoint = llmEndpoint == "mlx_local" && !litellmLocal.enable;
  apiKeyEnvVar =
    if litellmLocal.enable then
      "OPENAI_API_KEY"
    else if isLocalEndpoint then
      "QWEN_LOCAL_DUMMY_KEY"
    else
      "OPENAI_API_KEY";
  providerKey = "mlx-local-llama-swap";

  # The qwen-code model schema only accepts `name` and `description` — routing
  # is implicit in the provider's baseUrl, not a per-model field. When the
  # endpoint is the router or local proxy, expose only its capability aliases.
  routerAliases = litellmLocal.aliases;
  isRouterEndpoint = litellmLocal.enable || llmEndpoint == "router";
  modelEntries =
    if isRouterEndpoint then
      map (name: {
        inherit name;
        description = "${name} router capability";
      }) routerAliases
    else
      lib.mapAttrsToList (role: physical: {
        name = role;
        description = "${role} → ${physical}";
      }) config.services.aiStack.models;
  staticModelProviders = map (
    modelName:
    let
      modelId = modelMode.modelId modelName;
    in
    {
      name = "mlx-static-resident";
      protocol = "openai";
      baseUrl = modelMode.endpoint modelName;
      # The static MLX server is an open loopback endpoint; Qwen Code still
      # requires an environment variable name in the provider schema.
      envKey = "QWEN_LOCAL_DUMMY_KEY";
      models = [
        {
          name = modelId;
          description = "${modelName} local MLX model";
        }
      ];
    }
  ) cfg.models;
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
    inherit (config.programs.aiMcp) facadeCanary facadeCanaryClients facadeServer;
    excluded = cfg.excludedMcpServers;
    normalize = server: normalizeMcpServer (mcpClient.bridgeEnvHeaders pkgs server);
    client = "qwen-code";
  };

  baseSettings = {
    inherit mcpServers;

    # Auto-approve / prompt / block rules from the shared permission engine.
    permissions = qwenPermissions;

    # Load repo AGENTS.md as instruction context, matching the other agents.
    context.fileName = [ "AGENTS.md" ];

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
  }
  // lib.optionalAttrs modelMode.bySize {
    modelProviders = staticModelProviders;
    env = {
      QWEN_LOCAL_DUMMY_KEY = "dummy";
    };
    model.name = modelMode.modelId cfg.model;
  };

  # Deep merge user extras over our base. recursiveUpdate replaces leaf
  # values, including lists — so modelProviders gets special handling:
  # base providers stay, user providers append. Everything else
  # (env entries, security, model.name) deep-merges normally.
  extraProviders = cfg.extraSettings.modelProviders or [ ];
  extraWithoutProviders = builtins.removeAttrs cfg.extraSettings [ "modelProviders" ];

  # qwen-code reads modelProviders as `{ <authType> = [ model ]; }`, one flat
  # entry per model carrying its own baseUrl/envKey (a list here is skipped
  # whole as "Invalid authType key"). Providers stay the authoring shape;
  # each expands to its models, with an optional provider-level
  # generationConfig (e.g. `timeout` in ms) copied onto every model.
  toModelEntries =
    p:
    map (
      m:
      {
        id = m.name;
        inherit (m) name;
        inherit (p) baseUrl envKey;
      }
      // lib.optionalAttrs (m ? description) { inherit (m) description; }
      // lib.optionalAttrs (p ? generationConfig) { inherit (p) generationConfig; }
    ) p.models;
  allProviders = baseSettings.modelProviders ++ extraProviders;

  finalSettings = (lib.recursiveUpdate baseSettings extraWithoutProviders) // {
    modelProviders = lib.foldl' (
      acc: p:
      acc
      // {
        ${p.protocol} = (acc.${p.protocol} or [ ]) ++ toModelEntries p;
      }
    ) { } allProviders;
  };

  settingsJson = pkgs.writeText "qwen-settings.json" (builtins.toJSON finalSettings);
in
{
  config = lib.mkMerge [
    {
      programs.qwen-code = {
        contextFileNames = baseSettings.context.fileName;
        mcpServerNames = lib.attrNames mcpServers;
        generatedSettings = finalSettings;
      };
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
