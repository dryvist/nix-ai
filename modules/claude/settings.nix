# Claude Code Settings
#
# Manages ~/.claude/settings.json via activation-time merge (not home.file symlink).
# Merges plugin marketplaces, permissions, hooks, etc.
#
# NOTE: Uses toClaudeMarketplaceFormat from lib/claude-registry.nix as
# SINGLE SOURCE OF TRUTH for marketplace format transformation.
#
# VALIDATION: Environment variable names are validated at build time against
# POSIX convention (^[A-Z_][A-Z0-9_]*$). Full JSON Schema validation against
# https://json.schemastore.org/claude-code-settings.json is available via
# `nix flake check` but requires network access.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude;
  homeDir = config.home.homeDirectory;

  # Import the single source of truth for marketplace formatting
  claudeRegistry = import ../../lib/claude-registry.nix { inherit lib; }; # lastUpdated not needed here
  inherit (claudeRegistry) toClaudeMarketplaceFormat;

  # Build the env attribute (merge user env vars with API_KEY_HELPER if enabled)
  # Environment variable names must match POSIX convention: ^[A-Z_][A-Z0-9_]*$
  envAttrs =
    cfg.settings.env
    // lib.optionalAttrs cfg.apiKeyHelper.enable {
      API_KEY_HELPER = "${homeDir}/${cfg.apiKeyHelper.scriptPath}";
    };

  # Validate POSIX environment variable names
  # POSIX requires: starts with letter or underscore, followed by letters, digits, or underscores
  # We enforce uppercase for convention: ^[A-Z_][A-Z0-9_]*$
  isValidEnvVarName = name: builtins.match "^[A-Z_][A-Z0-9_]*$" name != null;
  invalidEnvVars = lib.filterAttrs (name: _: !isValidEnvVarName name) envAttrs;

  # Build Claude Code JSON for enabled (non-disabled) MCP servers.
  # Stdio servers: { command, args, env? }
  # SSE/HTTP servers: { type, url, headers? }
  activeMcpServers = lib.filterAttrs (_: v: !v.disabled) cfg.mcpServers;
  mcpServersAttrs = lib.mapAttrs (
    _: v:
    if v.type == "stdio" then
      { inherit (v) command args; } // lib.optionalAttrs (v.env != { }) { inherit (v) env; }
    else
      { inherit (v) type url; } // lib.optionalAttrs (v.headers != { }) { inherit (v) headers; }
  ) activeMcpServers;

  # Static JSON overlay — keys merged into ~/.claude.json at activation time.
  # - mcpServers: Nix is sole manager; manual `claude mcp add --scope user` entries are overwritten.
  # - remoteControlAtStartup: only included when set (not null).
  # Project trust entries are generated at activation time by claude-json-merge.sh
  # (filesystem discovery cannot happen at Nix evaluation time in pure flake mode).
  claudeJsonOverlay = {
    mcpServers = mcpServersAttrs;
  }
  // lib.optionalAttrs (cfg.remoteControlAtStartup != null) {
    inherit (cfg) remoteControlAtStartup;
  };

  # Build the overlay as a pretty-printed JSON derivation
  claudeJsonOverlayFile =
    pkgs.runCommand "claude-json-overlay.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "json" ];
        json = builtins.toJSON claudeJsonOverlay;
      }
      ''
        jq '.' "$jsonPath" > $out
      '';

  # Build the settings object
  settings = {
    "$schema" = cfg.settings.schemaUrl;
    inherit (cfg.settings) alwaysThinkingEnabled cleanupPeriodDays skillListingBudgetFraction;
    inherit (cfg)
      autoUpdatesChannel
      teammateMode
      showTurnDuration
      ;
  }
  // lib.optionalAttrs (cfg.effortLevel != null) { inherit (cfg) effortLevel; }
  // lib.optionalAttrs (cfg.attribution != { }) { inherit (cfg) attribution; }
  // {

    # Permissions
    permissions = {
      inherit (cfg.settings.permissions) allow deny ask;
      inherit (cfg.settings) additionalDirectories;
    }
    // lib.optionalAttrs (cfg.settings.permissions.defaultMode != null) {
      inherit (cfg.settings.permissions) defaultMode;
    };

    # Plugin configuration
    # Uses toClaudeMarketplaceFormat (single source of truth from lib/claude-registry.nix)
    extraKnownMarketplaces = lib.mapAttrs toClaudeMarketplaceFormat cfg.plugins.marketplaces;

    enabledPlugins = cfg.plugins.enabled;

    # Environment variables (user-defined + apiKeyHelper if enabled)
  }
  // lib.optionalAttrs (cfg.settings.skillOverrides != { }) {
    inherit (cfg.settings) skillOverrides;
  }
  // lib.optionalAttrs (cfg.model != null) { inherit (cfg) model; }
  // lib.optionalAttrs (cfg.remoteControlAtStartup != null) { inherit (cfg) remoteControlAtStartup; }
  // lib.optionalAttrs (envAttrs != { }) { env = envAttrs; }

  # Status line (only include if script is configured)
  # Do NOT include empty statusLine object (breaks Claude Code schema)
  // lib.optionalAttrs (cfg.statusLine.enable && cfg.statusLine.script != null) {
    statusLine = {
      type = "command";
      command = "${homeDir}/.claude/statusline-command.sh";
    };
  }

  # Sandbox configuration (Dec 2025 feature)
  # Only include when sandbox is actually enabled to avoid confusing disabled state with configuration
  // lib.optionalAttrs cfg.settings.sandbox.enabled {
    sandbox = {
      inherit (cfg.settings.sandbox) enabled autoAllowBashIfSandboxed;
    }
    // lib.optionalAttrs (cfg.settings.sandbox.excludedCommands != [ ]) {
      inherit (cfg.settings.sandbox) excludedCommands;
    };
  };

  # All Nix-managed marketplaces need entries in known_marketplaces.json (Claude Code's actual registry).
  # Without this, Claude Code may resolve installLocation to a git-cloned path instead of the
  # Nix-managed symlink at ~/.claude/plugins/marketplaces/<name>. Writing installLocation for every
  # marketplace ensures the merge-json-settings overlay wins over any runtime-written paths.
  nixManagedMarketplaces = lib.filterAttrs (_: m: m.flakeInput != null) cfg.plugins.marketplaces;
  knownMarketplacesOverlay = lib.mapAttrs (
    name: m:
    let
      formatted = toClaudeMarketplaceFormat name m;
      marketplaceName = lib.last (lib.splitString "/" name);
    in
    {
      inherit (formatted) source;
      installLocation = "${homeDir}/.claude/plugins/marketplaces/${marketplaceName}";
      lastUpdated = "1970-01-01T00:00:00.000Z";
    }
  ) nixManagedMarketplaces;

  knownMarketplacesJson =
    pkgs.runCommand "known-marketplaces-overlay.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "json" ];
        json = builtins.toJSON knownMarketplacesOverlay;
      }
      ''
        jq '.' "$jsonPath" > $out
      '';

  # Pretty-print JSON
  settingsJson =
    pkgs.runCommand "claude-settings.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "json" ];
        json = builtins.toJSON settings;
      }
      ''
        jq '.' "$jsonPath" > $out
      '';

  # Status line script (if configured)
  statusLineScript = lib.optionalAttrs (cfg.statusLine.enable && cfg.statusLine.script != null) {
    ".claude/statusline-command.sh" = {
      text = cfg.statusLine.script;
      executable = true;
    };
  };

  # Hook scripts generator
  # Converts hook options to executable scripts in ~/.claude/hooks/
  hookFiles =
    let
      # Map of hook names to their filenames
      hookMapping = {
        preToolUse = "pre-tool-use.sh";
        postToolUse = "post-tool-use.sh";
        userPromptSubmit = "user-prompt-submit.sh";
        stop = "stop.sh";
        subagentStop = "subagent-stop.sh";
        sessionStart = "session-start.sh";
        sessionEnd = "session-end.sh";
      };

      # Generate a single hook file attribute
      mkHookFile =
        _hookName: fileName: hookValue:
        if hookValue == null then
          { }
        else if builtins.isPath hookValue then
          {
            ".claude/hooks/${fileName}" = {
              source = hookValue;
              executable = true;
            };
          }
        else
          {
            ".claude/hooks/${fileName}" = {
              text = hookValue;
              executable = true;
            };
          };

      # Generate all hook files
      allHookFiles = lib.mapAttrs' (
        hookName: fileName: lib.nameValuePair hookName (mkHookFile hookName fileName cfg.hooks.${hookName})
      ) hookMapping;

      # Merge all non-null hook files into a single attrset
      # Note: lib.mkMerge is for option values, not attrsets. Use foldl' for regular merging.
      mergedHookFiles = lib.foldl' (a: b: a // b) { } (builtins.attrValues allHookFiles);
    in
    mergedHookFiles;

in
{
  config = lib.mkIf cfg.enable {
    # Merge runtime keys into ~/.claude.json (global config) at activation time.
    # These keys live in the global config file, not settings.json, so home.file cannot be
    # used directly (the file is runtime-mutable). One unified script deep-merges all keys.
    home.activation = {
      claudeJsonMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${pkgs.jq}/bin:$PATH"
        OVERLAY_FILE="${claudeJsonOverlayFile}"
        TRUSTED_PROJECT_DIRS=${lib.escapeShellArg (builtins.toJSON cfg.trustedProjectDirs)}
        . ${./scripts/claude-json-merge.sh}
      '';

      claudeSettingsMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${pkgs.jq}/bin:$PATH"
        $DRY_RUN_CMD ${../scripts/merge-json-settings.sh} \
          "${settingsJson}" \
          "${homeDir}/.claude/settings.json"
      '';

      # Ensure Nix-managed marketplaces are in known_marketplaces.json (Claude Code's actual registry).
      # Claude Code populates this by fetching from GitHub, but synthetic marketplaces (repos without
      # .claude-plugin structure) fail the fetch. This merge ensures the local installLocation is
      # registered so Claude Code reads the synthetic marketplace from the Nix-managed symlink.
      # install* activations (installBrowserUse, installOpenWebui) declare a dependency on this step
      # so a failing uv/npm install cannot abort the activation before the critical file merge runs
      # (activation uses set -eu).
      knownMarketplacesMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${pkgs.jq}/bin:$PATH"
        $DRY_RUN_CMD ${../scripts/merge-json-settings.sh} \
          "${knownMarketplacesJson}" \
          "${homeDir}/.claude/plugins/known_marketplaces.json"
      '';
    };

    # Validate configuration before generating settings.json
    assertions = [
      {
        assertion = invalidEnvVars == { };
        message = ''
          Invalid environment variable names in programs.claude.settings.env:
            ${lib.concatStringsSep ", " (builtins.attrNames invalidEnvVars)}

          Environment variable names must match POSIX convention: ^[A-Z_][A-Z0-9_]*$
          (uppercase letters, digits, and underscores only; must start with letter or underscore)
        '';
      }
      {
        assertion = lib.all (v: v.type != "stdio" || v.command != null) (
          builtins.attrValues cfg.mcpServers
        );
        message = ''
          MCP servers with type "stdio" must have a command set.
          Check programs.claude.mcpServers for entries with type = "stdio" and command = null.
        '';
      }
      {
        assertion = lib.all (v: v.type == "stdio" || v.url != null) (builtins.attrValues cfg.mcpServers);
        message = ''
          MCP servers with type "sse" or "http" must have a url set.
          Check programs.claude.mcpServers for entries with type = "sse"/"http" and url = null.
        '';
      }
    ];

    home.file = { } // statusLineScript // hookFiles;

  };
}
