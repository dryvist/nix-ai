# OpenCode Module
#
# Binary from nixpkgs; config declarative. OpenCode never
# rewrites its global config — state lives in ~/.local/share/opencode — so
# opencode.json is a plain declarative home.file, no deep-merge activation.
#
# Skills arrive via the shared agent-skills registry and native discovery.
# Commands are linked per-file from commandDirs so future sources coexist.
{
  pkgs,
  config,
  lib,
  llm-agents,
  userConfig,
  ...
}:

let
  cfg = config.programs.opencode;
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  inherit (cfg) configDir;
  inherit (config.programs) litellmLocal;

  otelPlugins = import ./otel-plugin.nix {
    inherit lib userConfig;
    username = config.home.username;
  };

  agentSkills = config.programs.agentSkills;
  skillRoot = ".${agentSkills.root}/skills";
  userInvokedSkills = builtins.filter (
    skill: skill.userInvoked && agentSkills.deployedSkillPaths ? "${skillRoot}/${skill.name}"
  ) agentSkills.fromFlakeInputs;

  # OpenCode ignores Claude's invocation flag. Native commands load manual
  # workflows explicitly while skill permissions hide them from model selection.
  skillCommands = lib.listToAttrs (
    map (skill: {
      inherit (skill) name;
      value = {
        description = "Run the ${skill.name} skill";
        template = ''
          Follow the ${skill.name} skill in @${config.home.homeDirectory}/${skillRoot}/${skill.name}/SKILL.md.
          Load reusable skills through the native skill tool; resolve supporting
          files relative to the referenced skill directory.

          User arguments: $ARGUMENTS
        '';
      };
    }) userInvokedSkills
  );
  mcpClient = import ../mcp/client.nix { inherit lib; };

  # The wall drops everything else, so credentials in the caller's shell never
  # reach it. The local LiteLLM key is a placeholder; the proxy checks no key.
  sandboxEnv = {
    OPENCODE_DISABLE_LSP_DOWNLOAD = "true";
    OPENCODE_DISABLE_PROJECT_CONFIG = "true";
  }
  // lib.optionalAttrs litellmLocal.enable { LITELLM_LOCAL_KEY = litellmLocal.clientToken; };

  trustedOpencode = import ./trusted.nix { inherit pkgs lib; } {
    inherit (cfg) package launchPrefix;
  };

  # Keep the Seatbelt launcher available as `opencode-wall`.
  sandboxedOpencode = import ./sandbox.nix { inherit pkgs lib; } {
    inherit (cfg) package;
    home = config.home.homeDirectory;
    workRoot = cfg.sandbox.workRoot;
    localPorts = lib.optional litellmLocal.enable litellmLocal.port;
    extraEnv = sandboxEnv;
    binaryName = "opencode-wall";
    realBinaryName = "opencode";
    inheritedEnv = [
      "AGENT_ROUTER_BASE_URL"
      "AGENT_ROUTER_LOCAL_KEY"
    ];
  };

  # opencode.json uses a local/remote-tagged MCP schema: local servers carry a
  # single `command` array (argv0 included) and `environment`; remote servers
  # carry `url` and optional `headers`. `enabled` defaults true, so it is
  # omitted. Verified against https://opencode.ai/config.json.
  normalizeMcpServer =
    server:
    if server.url != null then
      {
        type = "remote";
        inherit (server) url;
      }
      // lib.optionalAttrs (server.headers != { }) { inherit (server) headers; }
    else
      {
        type = "local";
        command = [ server.command ] ++ server.args;
      }
      // lib.optionalAttrs (server.env != { }) { environment = server.env; };

  mcpServers = mcpClient.renderServers {
    inherit (config.programs.aiMcp) enabledServers;
    excluded = cfg.excludedMcpServers;
    normalize = normalizeMcpServer;
    client = "opencode";
  };

  # Router aliases are names only; the homelab router owns their mappings.
  litellmRoles = import ../litellm-local/aliases.nix;
  goModels = [
    {
      alias = "go-mimo-flash";
      id = "mimo-v2.6-flash";
      protocol = "openai";
    }
    {
      alias = "go-deepseek-flash";
      id = "deepseek-v4.1-flash";
      protocol = "openai";
    }
    {
      alias = "go-glm-flash";
      id = "glm-5.3-flash";
      protocol = "openai";
    }
    {
      alias = "go-kimi-k3";
      id = "kimi-k3";
      protocol = "openai";
    }
    {
      alias = "go-qwen-plus";
      id = "qwen3.7-plus";
      protocol = "anthropic";
    }
    {
      alias = "go-minimax-m3";
      id = "minimax-m3";
      protocol = "anthropic";
    }
  ];
  goAliases = map (model: model.alias) goModels;
  routerModels = lib.unique (litellmRoles ++ goAliases ++ cfg.extraModels);
  localMlxModels = lib.unique (litellmRoles ++ cfg.extraModels);
  goModelAttrs =
    models:
    lib.listToAttrs (
      map (model: {
        name = model.alias;
        value = {
          name = model.alias;
          inherit (model) id;
        };
      }) models
    );
  goOpenAIModels = goModelAttrs (builtins.filter (model: model.protocol == "openai") goModels);
  goAnthropicModels = goModelAttrs (builtins.filter (model: model.protocol == "anthropic") goModels);
  localRouterAlias = "medium";
  localRouterAgent =
    assert builtins.elem localRouterAlias litellmRoles;
    {
      description = "Delegate to the router's `${localRouterAlias}` capability (resolved upstream, never a physical model)";
      mode = "subagent";
      model = "router/${localRouterAlias}";
    };

  settings = {
    "$schema" = "https://opencode.ai/config.json";
    permission = "allow";
    command = skillCommands;
    mcp = mcpServers;
    provider = {
      router = {
        npm = "@ai-sdk/openai-compatible";
        name = "router";
        options = {
          baseURL = "{env:AGENT_ROUTER_BASE_URL}";
          apiKey = "{env:AGENT_ROUTER_LOCAL_KEY}";
        };
        models.${localRouterAlias}.name = localRouterAlias;
      };
      litellm = {
        npm = "@ai-sdk/openai-compatible";
        name = "LiteLLM (router)";
        options = {
          baseURL = "{env:LLM_ROUTER_URL}";
          apiKey = "{env:AGENT_ROUTER_KEY}";
        };
        models = lib.genAttrs routerModels (name: {
          inherit name;
        });
      };
      opencode-go = {
        npm = "@ai-sdk/openai-compatible";
        name = "OpenCode Go";
        options = {
          baseURL = "https://opencode.ai/zen/go/v1";
          apiKey = "{env:OPENCODE_API_KEY}";
        };
        models = goOpenAIModels;
      };
      opencode-go-anthropic = {
        npm = "@ai-sdk/anthropic";
        name = "OpenCode Go (Anthropic)";
        options = {
          baseURL = "https://opencode.ai/zen/go/v1";
          apiKey = "{env:OPENCODE_API_KEY}";
        };
        models = goAnthropicModels;
      };
    }
    // lib.optionalAttrs litellmLocal.enable {
      mlx = {
        npm = "@ai-sdk/openai-compatible";
        name = "MLX (local)";
        options = {
          baseURL = litellmLocal.baseUrl;
          apiKey = "{env:LITELLM_LOCAL_KEY}";
        };
        models = lib.genAttrs localMlxModels (name: {
          inherit name;
        });
      };
    };
    agent = {
      local = localRouterAgent;
    }
    // (lib.genAttrs litellmRoles (role: {
      description = "Delegate to the router's `${role}` capability (resolved upstream, never a physical model)";
      mode = "subagent";
      model = "litellm/${role}";
    }));
    # LSP integration is off by default upstream; this enables every built-in
    # server. A server only activates when its binary is on PATH, so the set
    # in use is whatever nix-home ships globally (see its core.nix "Language
    # Servers" section). OPENCODE_DISABLE_LSP_DOWNLOAD below keeps OpenCode
    # from fetching any missing server from GitHub releases out-of-band.
    lsp = true;
  }
  // lib.optionalAttrs (otelPlugins != [ ]) { plugin = otelPlugins; }
  # Route OpenCode's default and small background tier through the matching
  # router capabilities. The provider catalog and delegated agents share the
  # alias contract from modules/litellm-local/aliases.nix.
  // {
    model = "litellm/medium";
    small_model = "litellm/small";
  };

  # Pretty-printed via jq (same convention as copilot.nix / antigravity-cli):
  # builtins.toJSON is compact, so a runCommand + jq '.' derivation produces the
  # human-readable layout the other harness configs use.
  settingsJson =
    pkgs.runCommand "opencode.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        json = builtins.toJSON (lib.recursiveUpdate settings cfg.extraSettings);
        passAsFile = [ "json" ];
      }
      ''
        jq '.' "$jsonPath" > $out
      '';

  mdFiles =
    dir:
    lib.optionalAttrs (builtins.pathExists dir) (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (builtins.readDir dir)
    );

  mkCommandLinks =
    dir:
    lib.mapAttrs' (name: _: {
      name = "${configDir}/command/${name}";
      value = {
        source = "${dir}/${name}";
      };
    }) (mdFiles dir);
in
{
  imports = [ ./options.nix ];

  # Shadow home-manager 26.05's upstream programs.opencode module — this
  # module owns the option namespace (same pattern as antigravity-cli).
  disabledModules = [ "programs/opencode.nix" ];

  config = lib.mkMerge [
    # Read-only introspection option set unconditionally so module evaluation
    # (and the shared MCP renderer-parity check) succeeds even when
    # programs.opencode.enable = false.
    {
      programs.opencode = {
        mcpServerNames = lib.attrNames mcpServers;
        inherit litellmRoles;
        lspEnabled = settings.lsp or false;
        otelPluginEntries = otelPlugins;
      };
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !cfg.sandbox.enable || pkgs.stdenv.hostPlatform.isDarwin;
          message = "programs.opencode.sandbox.enable needs macOS: the Seatbelt profile is applied by /usr/bin/sandbox-exec.";
        }
      ];

      # llm-agents.nix packages opencode for both supported systems, so the
      # binary is no longer "installed out-of-band" — that gap is why a Linux
      # host got config with nothing to run it.
      #
      # Sourced from llm-agents rather than nixpkgs because it tracks upstream
      # far more closely (1.18.29 against 26.05's 1.15.10). Unlike codex there
      # is no Homebrew cask involved: one owner on every platform.
      programs.opencode.package = lib.mkDefault llmAgents.opencode;

      home = {
        packages =
          lib.optional (cfg.package != null) trustedOpencode
          ++ lib.optional (cfg.package != null && cfg.sandbox.enable) sandboxedOpencode;

        # Every language server OpenCode should use is Nix-provided on PATH
        # (modules/ai-tools.nix + per-repo devShells). Its built-ins
        # auto-download from GitHub releases when a binary is missing — the
        # download prompt was declined twice (lsp-install-decisions.json), so
        # keep Nix the only source and let a missing server fail loudly
        # instead.
        sessionVariables = {
          OPENCODE_DISABLE_LSP_DOWNLOAD = "true";
        }
        // lib.optionalAttrs (config.services.aiStack.llmRouterEndpoint != "") {
          LLM_ROUTER_URL = config.services.aiStack.llmRouterEndpoint;
        };

        file = {
          "${configDir}/opencode.json".source = settingsJson;
          # The session hook sets OpenCode's current session ID on Go group
          # calls routed through LiteLLM; direct Go providers use the same hook.
          "${configDir}/plugins/go-session.js".source = ./plugins/go-session.js;
        }
        // lib.foldl' (acc: dir: acc // mkCommandLinks dir) { } cfg.commandDirs;
      };
    })
  ];
}
