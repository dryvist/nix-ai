# Gemini Settings Generation
#
# Generates settings.json and a Policy Engine TOML file.
# settings.json is NOT a read-only symlink — Gemini writes auth tokens
# and runtime state to this file.
#
# POLICY ENGINE (Gemini CLI v0.36+):
# Replaces deprecated tools.allowed and tools.exclude with TOML policy rules.
# Rules use commandPrefix for shell commands and toolName for built-in tools.
# Docs: https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/policy-engine.md
{
  pkgs,
  config,
  lib,
  ai-assistant-instructions,
  ...
}:

let
  cfg = config.programs.gemini;
  homeDir = config.home.homeDirectory;
  gitDir = "${homeDir}/git";

  aiCommon = import ../common {
    inherit lib config ai-assistant-instructions;
  };
  inherit (aiCommon) permissions formatters;

  defaultTrustedFolders = [
    "${homeDir}/.config/nix"
    gitDir
  ];

  # Default paths the sandbox may write to. Merged with cfg.sandboxAllowedPaths
  # so every bare repo under ~/git/ can create worktrees without a denial.
  defaultSandboxAllowedPaths = [ gitDir ];

  mergedSandboxAllowedPaths = lib.unique (defaultSandboxAllowedPaths ++ cfg.sandboxAllowedPaths);

  # Normalize MCP server for Gemini format
  # stdio: { command, args?, env?, cwd?, timeout? }
  # HTTP/SSE: { httpUrl, headers? } (note: httpUrl not url)
  normalizeGeminiMcpServer =
    server:
    if server.url != null then
      # HTTP/SSE server
      { httpUrl = server.url; } // lib.optionalAttrs (server.headers != { }) { inherit (server) headers; }
    else
      # stdio server
      lib.filterAttrs (_name: value: value != null && value != [ ] && value != { }) (
        {
          command = server.command or null;
          args = server.args or [ ];
          env = server.env or { };
        }
        // lib.optionalAttrs (server ? cwd) { inherit (server) cwd; }
        // lib.optionalAttrs (server ? timeout) { inherit (server) timeout; }
      );

  mcpServers =
    lib.mapAttrs' (name: server: lib.nameValuePair name (normalizeGeminiMcpServer server))
      (
        lib.filterAttrs (
          name: server: !(server.disabled or false) && !(lib.elem name cfg.excludedMcpServers)
        ) config.programs.aiMcp.servers
      );

  # Policy Engine: generate TOML rules from shared permissions
  policyRules =
    formatters.gemini.formatAllowRules permissions
    ++ formatters.gemini.formatDenyRules permissions
    ++ formatters.gemini.formatAskRules permissions;

  policyToml = (pkgs.formats.toml { }).generate "gemini-policy.toml" {
    rule = policyRules;
  };

  # Path where the policy file will be deployed (must be absolute for policyPaths)
  policyPath = "${homeDir}/.gemini/policies/nix-managed.toml";

  settings = {
    "$schema" =
      "https://raw.githubusercontent.com/google-gemini/gemini-cli/main/schemas/settings.schema.json";

    # Policy Engine: reference the Nix-managed TOML policy file
    policyPaths = [ policyPath ];

    general = {
      previewFeatures = true;
      disableAutoUpdate = true;
    }
    // lib.optionalAttrs (cfg.defaultApprovalMode != null) {
      inherit (cfg) defaultApprovalMode;
    };

    context = {
      fileName = [ "AGENTS.md" ];
    };

    security = {
      folderTrust = {
        enabled = true;
        trustedFolders = lib.unique (defaultTrustedFolders ++ cfg.trustedFolders);
      };
    };

    tools = {
      sandbox = if cfg.sandbox.profile != null then cfg.sandbox.profile else cfg.sandbox.enable;
      sandboxAllowedPaths = mergedSandboxAllowedPaths;
    };

    experimental = {
      inherit (cfg) worktrees;
    };

    inherit mcpServers;
  };

  settingsJson =
    pkgs.runCommand "gemini-settings.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        json = builtins.toJSON settings;
        passAsFile = [ "json" ];
      }
      ''
        jq '.' "$jsonPath" > $out
      '';
in
{
  config = lib.mkIf cfg.enable {
    programs.gemini.contextFileNames = settings.context.fileName;
    programs.gemini.sandboxAllowedPathsMerged = mergedSandboxAllowedPaths;

    home = {
      # Deploy the Policy Engine TOML file (read-only is fine — Gemini only reads it)
      file."${lib.removePrefix "${homeDir}/" policyPath}".source = policyToml;

      activation.mergeGeminiSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${pkgs.jq}/bin:$PATH"
        $DRY_RUN_CMD ${../scripts/merge-json-settings.sh} \
          "${settingsJson}" \
          "${homeDir}/.gemini/settings.json"
        $DRY_RUN_CMD ${../scripts/strip-deprecated-gemini-keys.sh} \
          "${homeDir}/.gemini/settings.json"
      '';
    };
  };
}
