# Antigravity (not CLI) Configuration Module
#
# Declarative configuration for Google Antigravity Desktop IDE.
# Generates mcp_config.json with shared MCP servers and updates all
# local project configuration files under ~/.gemini/config/projects/
# to elevate permissions and enable command auto-execution.
{
  config,
  lib,
  pkgs,
  ai-assistant-instructions,
  ...
}:

let
  cfg = config.programs.antigravity-ide;
  homeDir = config.home.homeDirectory;

  aiCommon = import ../common {
    inherit lib config ai-assistant-instructions;
  };
  inherit (aiCommon) permissions formatters;

  # Format permissions for Antigravity Desktop app (permissionGrants)
  # The format is "command(cmd)"
  allowedCommands = formatters."antigravity-ide".formatAllowed permissions;

  mcpServers =
    lib.mapAttrs' (name: server: lib.nameValuePair name (formatters.utils.normalizeMcpServer server))
      (
        lib.filterAttrs (
          name: server: !(server.disabled or false) && !(lib.elem name cfg.excludedMcpServers)
        ) config.programs.aiMcp.servers
      );

  mcpConfig = {
    inherit mcpServers;
  };

  mcpConfigJson =
    pkgs.runCommand "antigravity-mcp-config.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        json = builtins.toJSON mcpConfig;
        passAsFile = [ "json" ];
      }
      ''
        jq '.' "$jsonPath" > $out
      '';

  allowedCommandsJson = builtins.toJSON allowedCommands;
in
{
  options.programs.antigravity-ide = {
    enable = lib.mkEnableOption "Antigravity IDE configuration";

    autoExecutionPolicy = lib.mkOption {
      type = lib.types.str;
      default = "CASCADE_COMMANDS_AUTO_EXECUTION_EAGER";
      description = "Default auto execution policy for commands.";
    };

    fileAccessPolicy = lib.mkOption {
      type = lib.types.str;
      default = "AGENT_SETTING_POLICY_ALLOW";
      description = "Default file access policy.";
    };

    internetPolicy = lib.mkOption {
      type = lib.types.str;
      default = "AGENT_SETTING_POLICY_ALLOW";
      description = "Default internet policy.";
    };

    artifactReviewMode = lib.mkOption {
      type = lib.types.str;
      default = "ARTIFACT_REVIEW_MODE_NEVER";
      description = "Default artifact review mode.";
    };

    excludedMcpServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cloudflare"
        "cribl"
        "docker"
        "everything"
        "exa"
        "fetch"
        "filesystem"
        "firecrawl"
        "git"
        "github"
        "terraform"
      ];
      description = "MCP servers to exclude from the shared definitions";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      activation.mergeAntigravityIdeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Merge global settings for Antigravity IDE (VS Code-based settings.json)
        settings_file="${homeDir}/Library/Application Support/Antigravity/User/settings.json"
        if [ -f "$settings_file" ]; then
          export PATH="${pkgs.jq}/bin:$PATH"
          echo "-> Merging global settings for Antigravity IDE..."
          # Update or add the autoExecutionPolicy setting
          $DRY_RUN_CMD jq --arg policy "always" '. + {"antigravity.agent.terminal.autoExecutionPolicy": $policy}' "$settings_file" > "$settings_file.tmp" \
            && $DRY_RUN_CMD mv "$settings_file.tmp" "$settings_file"
        fi

        # Merge mcp_config.json
        export PATH="${pkgs.jq}/bin:$PATH"
        $DRY_RUN_CMD ${../scripts/merge-json-settings.sh} \
          "${mcpConfigJson}" \
          "${homeDir}/.gemini/config/mcp_config.json"

        # Update all project config JSON files under ~/.gemini/config/projects/
        projects_dir="${homeDir}/.gemini/config/projects"
        if [ -d "$projects_dir" ]; then
          echo "-> Elevating permissions for all Antigravity projects..."
          # Iterate over all json files in ~/.gemini/config/projects/
          find "$projects_dir" -name "*.json" -print0 | while IFS= read -r -d $'\0' project_file; do
            # We want to merge the new settings and allowed command list
            # We construct a jq script to update settings and permissionGrants.permissionGrants.allow
            # We combine and deduplicate them to be safe
            $DRY_RUN_CMD jq \
              --arg fileAccessPolicy "${cfg.fileAccessPolicy}" \
              --arg internetPolicy "${cfg.internetPolicy}" \
              --arg autoExecutionPolicy "${cfg.autoExecutionPolicy}" \
              --arg artifactReviewMode "${cfg.artifactReviewMode}" \
              --argjson allowedCommands '${allowedCommandsJson}' \
              '
              .settings.fileAccessPolicy = $fileAccessPolicy |
              .settings.internetPolicy = $internetPolicy |
              .settings.autoExecutionPolicy = $autoExecutionPolicy |
              .settings.artifactReviewMode = $artifactReviewMode |
              (.permissionGrants.permissionGrants.allow // []) as $existing_allow |
              .permissionGrants.permissionGrants.allow = ($existing_allow + $allowedCommands | unique)
              ' \
              "$project_file" > "$project_file.tmp" \
              && $DRY_RUN_CMD mv "$project_file.tmp" "$project_file"
          done
        fi
      '';
    };
  };
}
