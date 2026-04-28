# Codex Settings Generation
#
# Generates config.toml and manages the activation merge.
# config.toml is NOT a read-only symlink — Codex writes to it at runtime.
# We use an activation script that deep-merges Nix defaults with runtime state.
{
  pkgs,
  config,
  lib,
  ai-assistant-instructions,
  ...
}:

let
  cfg = config.programs.codex;
  homeDir = config.home.homeDirectory;

  aiCommon = import ../common {
    inherit lib config ai-assistant-instructions;
  };
  inherit (aiCommon) permissions formatters;

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

  mcpServers = lib.mapAttrs' (name: server: lib.nameValuePair name (normalizeMcpServer server)) (
    lib.filterAttrs (
      name: server: !(server.disabled or false) && !(lib.elem name cfg.excludedMcpServers)
    ) config.programs.aiMcp.servers
  );

  optionalValue = key: value: lib.optionalAttrs (value != null) { ${key} = value; };

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
  };

  configJson = pkgs.writeText "codex-config.json" (builtins.toJSON configAttrs);
  configToml = pkgs.runCommand "codex-config.toml" { nativeBuildInputs = [ pkgs.yj ]; } ''
    yj -jt < ${configJson} > $out
  '';
in
{
  config = lib.mkIf cfg.enable {
    programs.codex.projectDocFallbackFilenames = configAttrs.project_doc_fallback_filenames;

    home = {
      activation.codexConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${pkgs.jq}/bin:${pkgs.yj}/bin:$PATH"
        $DRY_RUN_CMD ${../scripts/merge-toml-settings.sh} \
          "${configToml}" \
          "${homeDir}/.codex/config.toml"
      '';

      file."${configDir}/rules/default.rules".text = formatters.codex.formatRulesFile permissions;
    };
  };
}
