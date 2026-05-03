#
# Aider Module - Settings Generation
#
# Generates three read-only files via home.file (Aider does NOT rewrite them):
#
#   ~/.aider.conf.yml             Main config; picked up before project-level overrides
#   ~/.aider/aider-meta.json      Context limits / cost data for local MLX models
#   ~/.aider/aider-settings.yml   Per-model edit format and streaming overrides
#
# All three files are read-only Nix-store symlinks - no activation merge script
# needed because Aider treats them as static config, not runtime state.
#
{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.programs.aider;
  homeDir = config.home.homeDirectory;

  # Endpoint selection: llama-swap (default) or Bifrost

  isBifrost = cfg.routing == "bifrost";

  endpointBase = if isBifrost then "http://localhost:30080/v1" else "http://127.0.0.1:11434/v1";

  # Model name resolution:
  # llama-swap routing: keep openai/<role> - llama-swap resolves via useModelName.
  # Bifrost routing: convert to openai/mlx-local/<physical-hf-id> - Bifrost
  # requires the mlx-local/ prefix to route to the local MLX stack.

  inherit (config.services.aiStack) models;

  prefixModel =
    m:
    let
      n = lib.removePrefix "openai/" m;
    in
    if isBifrost then "openai/mlx-local/" + (models.${n} or n) else m;

  prefixedWeakModel = prefixModel cfg.weakModel;

  yamlFormat = pkgs.formats.yaml { };

  # History and metadata file paths, extracted to let-bindings so that
  # quoted-key attrset bindings below use plain identifiers as values
  # (avoids statix W04 cross-boundary false positives on quoted keys).
  pathChatHistory = "${homeDir}/.aider/history/aider-chat.md";
  pathInputHistory = "${homeDir}/.aider/history/aider-input";
  pathLlmHistory = "${homeDir}/.aider/history/aider-llm.md";
  pathModelMeta = "${homeDir}/.aider/aider-meta.json";
  pathModelSettings = "${homeDir}/.aider/aider-settings.yml";

  # Main Aider config
  #
  # History files use aider- prefixed names so their path components share no
  # prefix with the config-key names (chat-history-file, input-history-file, etc.)
  # Override via extraConfig to use different paths.

  configAttrs = {
    openai-api-base = endpointBase;
    openai-api-key = "dummy"; # llama-swap/Bifrost authenticate upstream; local hop is open
    model = prefixModel cfg.model;
    weak-model = prefixedWeakModel;
    editor-model = prefixModel cfg.editorModel;
    auto-commits = cfg.autoCommits;
    dirty-commits = cfg.dirtyCommits;
    attribute-author = cfg.attributeAuthor;
    attribute-committer = cfg.attributeCommitter;
    inherit (cfg)
      gitignore
      lint
      pretty
      stream
      ;
    auto-test = cfg.autoTest;
    dark-mode = cfg.darkMode;
    read = cfg.readFiles;
  }
  // {
    "chat-history-file" = pathChatHistory;
    "input-history-file" = pathInputHistory;
    "llm-history-file" = pathLlmHistory;
    "model-metadata-file" = pathModelMeta;
    "model-settings-file" = pathModelSettings;
  }
  // cfg.extraConfig;

  yamlConf = yamlFormat.generate "aider-conf.yml" configAttrs;

  # Model metadata
  #
  # Aider uses LiteLLM; unknown models fall back to GPT-4 limits which may be
  # wrong. Generate entries for both naming conventions:
  #   - openai/<role>            used with llama-swap routing
  #   - openai/mlx-local/<id>   used with Bifrost routing

  metadataEntry = {
    max_input_tokens = 32768;
    max_output_tokens = 8192;
    input_cost_per_token = 0;
    output_cost_per_token = 0;
  };

  roleAliasMetadata = lib.mapAttrs' (
    role: _: lib.nameValuePair "openai/${role}" metadataEntry
  ) models;

  physicalIdMetadata = lib.mapAttrs' (
    _: physicalId: lib.nameValuePair "openai/mlx-local/${physicalId}" metadataEntry
  ) models;

  modelMetadata = roleAliasMetadata // physicalIdMetadata;

  metadataJson = pkgs.writeText "aider-model-metadata.json" (builtins.toJSON modelMetadata);

  # Model settings
  #
  # Per-model edit format and streaming overrides. Entries for:
  #   - each role alias (llama-swap routing)
  #   - each physical HF id with mlx-local/ prefix (Bifrost routing)
  # A catch-all regex entry covers additional openai/mlx-local/* variants
  # that might appear if the user extends services.aiStack.models later.

  codeRoles = [
    "default"
    "coding"
    "tool-calling"
    "most-capable"
    "large-context"
    "oss"
  ];

  makeSettingsEntry =
    name: role:
    let
      selectedFormat = if lib.elem role codeRoles then cfg.editFormat else cfg.weakEditFormat;
    in
    {
      inherit name;
      weak_model_name = prefixedWeakModel;
      use_repo_map = true;
      streaming = cfg.stream;
    }
    // lib.optionalAttrs (selectedFormat != null) { edit_format = selectedFormat; };

  roleAliasSettings = lib.mapAttrsToList (role: _: makeSettingsEntry "openai/${role}" role) models;

  physicalIdSettings = lib.mapAttrsToList (
    role: physicalId: makeSettingsEntry "openai/mlx-local/${physicalId}" role
  ) models;

  # Regex catch-all for any mlx-local/* model not explicitly listed above;
  # "default" is a codeRole so this entry correctly inherits editFormat (not weakEditFormat).
  catchAllEntry = makeSettingsEntry "openai/mlx-local/.*" "default";

  modelSettings = roleAliasSettings ++ physicalIdSettings ++ [ catchAllEntry ];

  modelSettingsYaml = yamlFormat.generate "aider-model-settings.yml" modelSettings;

in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      ".aider.conf.yml".source = yamlConf;
      ".aider/aider-meta.json".source = metadataJson;
      ".aider/aider-settings.yml".source = modelSettingsYaml;
      ".aider/history/.keep".text = "# Managed by Nix - programs.aider\n";
    };
  };
}
