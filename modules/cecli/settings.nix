#
# cecli Module — Settings Generation
#
# Generates three read-only files via home.file (cecli does NOT rewrite them):
#
#   ~/.cecli.conf.yml             Main config; picked up before project-level overrides
#   ~/.cecli/cecli-meta.json      Context limits / cost data for local MLX models
#   ~/.cecli/cecli-settings.yml   Per-model edit format and streaming overrides
#
# All three files are read-only Nix-store symlinks — cecli treats them as
# static config, not runtime state. cecli still uses litellm internally so
# the metadata format is unchanged from the previous Aider module.
#
{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.programs.cecli;
  homeDir = config.home.homeDirectory;

  endpointBase = "http://127.0.0.1:11434/v1";

  # Model names are openai/<role>; llama-swap resolves each role to the
  # physical HF id via useModelName (see services.aiStack.models).
  inherit (config.services.aiStack) models;

  yamlFormat = pkgs.formats.yaml { };

  pathChatHistory = "${homeDir}/.cecli/history/cecli-chat.md";
  pathInputHistory = "${homeDir}/.cecli/history/cecli-input";
  pathLlmHistory = "${homeDir}/.cecli/history/cecli-llm.md";
  pathModelMeta = "${homeDir}/.cecli/cecli-meta.json";
  pathModelSettings = "${homeDir}/.cecli/cecli-settings.yml";

  configAttrs = {
    openai-api-base = endpointBase;
    openai-api-key = "dummy"; # llama-swap authenticates upstream; local hop is open
    inherit (cfg) model;
    weak-model = cfg.weakModel;
    editor-model = cfg.editorModel;
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

  yamlConf = yamlFormat.generate "cecli-conf.yml" configAttrs;

  # Model metadata — cecli uses LiteLLM. Unknown models fall back to GPT
  # limits which may be wrong. Generate an entry per openai/<role> alias.
  metadataEntry = {
    max_input_tokens = 32768;
    max_output_tokens = 8192;
    input_cost_per_token = 0;
    output_cost_per_token = 0;
  };

  modelMetadata = lib.mapAttrs' (role: _: lib.nameValuePair "openai/${role}" metadataEntry) models;

  metadataJson = pkgs.writeText "cecli-model-metadata.json" (builtins.toJSON modelMetadata);

  # Per-model edit format and streaming overrides — one entry per role alias.
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
      weak_model_name = cfg.weakModel;
      use_repo_map = true;
      streaming = cfg.stream;
    }
    // lib.optionalAttrs (selectedFormat != null) { edit_format = selectedFormat; };

  modelSettings = lib.mapAttrsToList (role: _: makeSettingsEntry "openai/${role}" role) models;

  modelSettingsYaml = yamlFormat.generate "cecli-model-settings.yml" modelSettings;

in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      ".cecli.conf.yml".source = yamlConf;
      ".cecli/cecli-meta.json".source = metadataJson;
      ".cecli/cecli-settings.yml".source = modelSettingsYaml;
      ".cecli/history/.keep".text = "# Managed by Nix - programs.cecli\n";
    };
  };
}
