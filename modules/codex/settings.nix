# Codex Settings Generation
#
# Generates config.toml and manages the activation merge.
# config.toml is NOT a read-only symlink — Codex writes to it at runtime.
# We use an activation script that deep-merges Nix defaults with runtime state.
{
  pkgs,
  config,
  lib,
  nix-claude-code,
  userConfig,
  ...
}:

let
  cfg = config.programs.codex;
  inherit (config.programs) litellmLocal;
  homeDir = config.home.homeDirectory;

  aiCommon = import ../common {
    inherit lib config nix-claude-code;
  };
  inherit (aiCommon) permissions formatters;

  mcpClient = import ../mcp/client.nix { inherit lib; };

  # Mirror upstream home-manager programs.codex path logic so rules/config.toml stay co-located.
  packageVersion = if cfg.package != null then lib.getVersion cfg.package else "0.2.0";
  isTomlConfig = lib.versionAtLeast packageVersion "0.2.0";
  useXdgDirectories = config.home.preferXdgDirectories && isTomlConfig;
  xdgConfigHome = lib.removePrefix "${homeDir}/" config.xdg.configHome;
  configDir = if useXdgDirectories then "${xdgConfigHome}/codex" else ".codex";

  writableRoots = [
    "${homeDir}/.codex"
  ]
  ++ lib.optional useXdgDirectories "${config.xdg.configHome}/codex";

  trustedProjects = lib.unique (
    (permissions.directories.development or [ ])
    ++ (permissions.directories.config or [ ])
    ++ cfg.trustedProjectDirs
  );

  normalizeMcpServer =
    server:
    let
      allowedKeys =
        if server.url != null then
          [
            "bearer_token_env_var"
            "disabled_tools"
            "enabled_tools"
            "env_http_headers"
            "http_headers"
            "oauth_resource"
            "required"
            "scopes"
            "startup_timeout_sec"
            "tool_timeout_sec"
            "url"
          ]
        else
          [
            "args"
            "command"
            "cwd"
            "disabled_tools"
            "enabled_tools"
            "env"
            "env_vars"
            "required"
            "startup_timeout_sec"
            "tool_timeout_sec"
          ];
    in
    lib.filterAttrs (
      name: value: lib.elem name allowedKeys && value != null && value != [ ] && value != { }
    ) server;

  mcpServers = mcpClient.renderServers {
    inherit (config.programs.aiMcp) enabledServers;
    excluded = cfg.excludedMcpServers;
    normalize = normalizeMcpServer;
    client = "codex";
  };

  optionalValue = key: value: lib.optionalAttrs (value != null) { ${key} = value; };

  # OpenTelemetry, sharing the one telemetry surface with Claude Code
  # (userConfig.telemetry) so both agents point at the same collector.
  #
  # Two things here differ from Claude Code and were measured, not assumed:
  #
  #  - Codex posts to the configured endpoint VERBATIM. Pointed at
  #    `http://host:port` it POSTs to `/`, appending no signal path — so this
  #    takes the full `/v1/traces` URL, the opposite of the generic
  #    OTEL_EXPORTER_OTLP_ENDPOINT that Claude Code uses as a base.
  #  - `protocol = "binary"` is OTLP/HTTP protobuf. The collector answers 501
  #    to JSON, so the encoding is load-bearing rather than cosmetic.
  #
  # metrics_exporter is pinned off: the collector's pipeline extracts spans
  # only, and Codex embeds an OTel SDK whose unset default is a conventional
  # loopback address — leaving it unset would export into nothing.
  telemetryEnabled =
    (userConfig.telemetry.enable or false) && (userConfig.telemetry.tracesEndpoint or null) != null;

  otelAttrs = lib.optionalAttrs telemetryEnabled {
    otel = {
      environment = "homelab";
      log_user_prompt = userConfig.telemetry.logUserPrompts or false;
      metrics_exporter = "none";
      trace_exporter.otlp-http = {
        endpoint = userConfig.telemetry.tracesEndpoint;
        protocol = "binary";
      };
    };
  };

  # Nix-managed defaults for config.toml.
  configAttrs = {
    approval_policy = cfg.approvalPolicy;
    personality = "pragmatic";
    project_doc_fallback_filenames = [ "AGENTS.md" ];
    projects = lib.listToAttrs (
      map (path: {
        name = path;
        value.trust_level = "trusted";
      }) trustedProjects
    );
    sandbox_mode = "workspace-write";
    sandbox_workspace_write = {
      network_access = false;
      writable_roots = writableRoots;
    };
    mcp_servers = mcpServers;
  }
  // optionalValue "model" cfg.model
  // optionalValue "model_provider" cfg.modelProvider
  // optionalValue "model_reasoning_effort" cfg.modelReasoningEffort
  // optionalValue "model_verbosity" cfg.modelVerbosity
  // optionalValue "plan_mode_reasoning_effort" cfg.planModeReasoningEffort
  // optionalValue "review_model" cfg.reviewModel
  // optionalValue "service_tier" cfg.serviceTier
  // optionalValue "web_search" cfg.webSearch
  // lib.optionalAttrs (cfg.features != { }) {
    inherit (cfg) features;
  }
  # Local LiteLLM proxy as an ADDITIONAL provider, not the default one: the
  # top-level model/model_provider above stay as they are, so the lead model
  # is unchanged. `codex --profile ox` is the opt-in that runs a job on the
  # `subagent` role instead.
  #
  # wire_api = "responses" because Codex speaks only the Responses API; the
  # proxy translates /v1/responses to chat for backends that lack it.
  // otelAttrs
  // lib.optionalAttrs litellmLocal.enable {
    model_providers.litellm = {
      name = "LiteLLM (local)";
      base_url = litellmLocal.baseUrl;
      wire_api = "responses";
      env_key = "LITELLM_LOCAL_KEY";
    };
  };

  # A Codex profile is a FILE, not a table in the config above. Codex dropped
  # the legacy `[profiles.<name>]` table (and the top-level `profile =`
  # selector) in 0.134.0: a config still carrying one is refused outright, so
  # `--profile <name>` failed to start rather than falling back. Each profile
  # now lives in its own `~/.codex/<name>.config.toml` with its keys at the
  # TOP level, selected the same way on the command line: `codex --profile
  # judge`. One profile per router capability alias
  # (modules/litellm-local/aliases.nix) — the committed contract every
  # nix-ai consumer renders from — replacing the single hardcoded `ox`
  # profile this used to be.
  litellmRoles = import ../litellm-local/aliases.nix;

  litellmProfileAttrs = lib.genAttrs litellmRoles (role: {
    model = role;
    model_provider = "litellm";
  });

  litellmProfileTomls = lib.mapAttrs (
    role: attrs:
    let
      json = pkgs.writeText "codex-${role}-profile.json" (builtins.toJSON attrs);
    in
    pkgs.runCommand "codex-${role}.config.toml" { nativeBuildInputs = [ pkgs.yj ]; } ''
      yj -jt < ${json} > $out
    ''
  ) litellmProfileAttrs;

  configJson = pkgs.writeText "codex-config.json" (builtins.toJSON configAttrs);
  configToml = pkgs.runCommand "codex-config.toml" { nativeBuildInputs = [ pkgs.yj ]; } ''
    yj -jt < ${configJson} > $out
  '';
in
{
  config = lib.mkMerge [
    # Read-only introspection option set unconditionally so module evaluation
    # succeeds even when programs.codex.enable = false.
    {
      programs.codex = {
        projectDocFallbackFilenames = configAttrs.project_doc_fallback_filenames;
        mcpServerNames = lib.attrNames mcpServers;
        litellmProfileNames = lib.attrNames litellmProfileTomls;
      };
    }
    # Codex reads hooks.json only behind this flag. A non-empty hooks.events
    # implies it, so every contributor (herdr, the worktree-add guard, …)
    # doesn't also have to remember to flip it on; mkDefault so an explicit
    # `programs.codex.features.hooks = false;` still wins.
    (lib.mkIf (cfg.enable && cfg.hooks.events != { }) {
      programs.codex.features.hooks = lib.mkDefault true;
    })
    (lib.mkIf cfg.enable {
      home = {
        activation.codexConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          export PATH="${pkgs.jq}/bin:${pkgs.yj}/bin:$PATH"
          $DRY_RUN_CMD ${../scripts/merge-toml-settings.sh} \
            "${configToml}" \
            "${homeDir}/.codex/config.toml"
        '';

        file = {
          "${configDir}/rules/default.rules".text = formatters.codex.formatRulesFile permissions;
        }
        // lib.optionalAttrs litellmLocal.enable (
          lib.mapAttrs' (
            role: toml: lib.nameValuePair "${configDir}/${role}.config.toml" { source = toml; }
          ) litellmProfileTomls
        )
        // lib.optionalAttrs (cfg.hooks.events != { }) {
          ".codex/hooks.json".source = pkgs.writers.writeJSON "codex-hooks.json" {
            hooks = cfg.hooks.events;
          };
        };
      };
    })
  ];
}
