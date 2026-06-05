# Antigravity Settings Generation
#
# Generates settings.json and a Policy Engine TOML file.
# settings.json is NOT a read-only symlink — Antigravity writes auth tokens
# and runtime state to this file.
#
# POLICY ENGINE (Antigravity CLI v0.36+):
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
  cfg = config.programs.antigravity-cli;
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
  defaultSandboxAllowedPaths = [ gitDir "${homeDir}/git/public" "${homeDir}/git/public/nix-darwin/.git" ];

  mergedSandboxAllowedPaths = lib.unique (defaultSandboxAllowedPaths ++ cfg.sandboxAllowedPaths);

  # Normalize MCP server for Antigravity format
  # stdio: { command, args?, env?, cwd?, timeout? }
  # HTTP/SSE: { httpUrl, headers? } (note: httpUrl not url)
  normalizeAntigravityMcpServer =
    server:
    if server.url != null then
      # HTTP/SSE server
      { httpUrl = server.url; } // lib.optionalAttrs (server.headers != { }) { inherit (server) headers; }
    else
      # stdio server
      lib.filterAttrs (_name: value: value != null && value != [ ] && value != { }) {
        inherit (server)
          command
          args
          env
          cwd
          timeout
          ;
      };

  mcpServers =
    lib.mapAttrs' (name: server: lib.nameValuePair name (normalizeAntigravityMcpServer server))
      (
        lib.filterAttrs (
          name: server: !(server.disabled or false) && !(lib.elem name cfg.excludedMcpServers)
        ) config.programs.aiMcp.servers
      );

  # Policy Engine: generate TOML rules from shared permissions
  policyRules =
    formatters."antigravity-cli".formatAllowRules permissions
    ++ formatters."antigravity-cli".formatDenyRules permissions
    ++ formatters."antigravity-cli".formatAskRules permissions;

  policyToml = (pkgs.formats.toml { }).generate "antigravity-policy.toml" {
    rule = policyRules;
  };

  # Path where the policy file will be deployed (must be absolute for policyPaths)
  policyPath = "${homeDir}/.gemini/antigravity-cli/policies/nix-managed.toml";

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
    }
    // lib.optionalAttrs cfg.gemmaModelRouter.enable {
      gemmaModelRouter = {
        enabled = true;
        inherit (cfg.gemmaModelRouter) autoStartServer binaryPath;
        classifier = {
          host = "http://localhost:${toString cfg.gemmaModelRouter.port}";
          model = cfg.gemmaModelRouter.classifierModel;
        };
      };
    };

    inherit mcpServers;
  }
  // lib.optionalAttrs (cfg.defaultModel != null) {
    model = {
      name = cfg.defaultModel;
    };
  };

  settingsJson =
    pkgs.runCommand "antigravity-settings.json"
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
  config = lib.mkMerge [
    # Read-only introspection options set unconditionally so module evaluation
    # succeeds even when programs.antigravity-cli.enable = false. Values are derived from
    # pure Nix expressions (no activation-time side effects).
    {
      programs.antigravity-cli.contextFileNames = settings.context.fileName;
      programs.antigravity-cli.sandboxAllowedPathsMerged = mergedSandboxAllowedPaths;
    }
    (lib.mkIf cfg.enable {
      home = {
        # Deploy the Policy Engine TOML file (read-only is fine — Antigravity only reads it)
        file."${lib.removePrefix "${homeDir}/" policyPath}".source = policyToml;

        activation.mergeAntigravitySettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          export PATH="${pkgs.jq}/bin:$PATH"
          $DRY_RUN_CMD ${../scripts/merge-json-settings.sh} \
            "${settingsJson}" \
            "${homeDir}/.gemini/antigravity-cli/settings.json"
          $DRY_RUN_CMD ${../scripts/strip-deprecated-antigravity-cli-keys.sh} \
            "${homeDir}/.gemini/antigravity-cli/settings.json"
        '';
      };
    })
  ];
}
