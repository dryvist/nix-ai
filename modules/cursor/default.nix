# Cursor CLI Module
#
# Installs and configures Cursor's terminal coding agent (`agent` /
# `cursor-agent`). The IDE stays installed via nix-darwin
# (home.packages = [ code-cursor ]) — this module only manages the CLI.
#
# The `code-cursor` IDE wrapper (`cursor agent`) requires the standalone CLI
# at ~/.local/bin/cursor-agent. The two symlinks here make the wrapper exec
# the nixpkgs binary instead of curl-installing its own copy, and put the
# official `agent` command name on PATH (curl installer contract: both names).
#
# Config files:
# - ~/.cursor/cli-config.json — deep-merge activation. The CLI rewrites this
#   file at runtime (self-repairing schema, permission list updates), so a
#   store symlink would break; merge-json-settings.sh overlays Nix-managed
#   keys onto existing runtime state (same pattern as codex config.toml).
# - ~/.cursor/mcp.json — declarative home.file. Cursor auto-detects this file
#   and never rewrites it at runtime (same rationale as opencode.json).
#
# Skills: Cursor natively reads ~/.agents/skills/ (plus ~/.claude/skills/ and
# ~/.codex/skills/), so an agent-skills registry symlink would double-scan the
# shared tree — same exclusion rationale as the Codex entry in
# modules/agent-skills/harnesses.nix.
{
  config,
  lib,
  pkgs,
  nix-claude-code,
  ...
}:

let
  cfg = config.programs.cursor;
  homeDir = config.home.homeDirectory;

  aiCommon = import ../common { inherit lib config nix-claude-code; };
  inherit (aiCommon) permissions formatters;

  mcpClient = import ../mcp/client.nix { inherit lib; };

  # Cursor MCP schema (~/.cursor/mcp.json): local servers carry a "stdio"
  # type tag plus command/args/env; remote servers carry a url plus optional
  # headers. The Cursor CLI parser only accepts type values "stdio", "http",
  # and "sse" — any other value makes it silently drop the whole file, so
  # remote servers must use "http" (Streamable HTTP; SSE is deprecated) rather
  # than OpenCode's "remote". The IDE ignores the type field and routes on
  # command/url. env values may use Cursor's ${env:NAME} / ${userHome}
  # interpolation — catalog values pass through untouched.
  normalizeMcpServer =
    server:
    if server.url != null then
      {
        type = "http";
        inherit (server) url;
      }
      // lib.optionalAttrs (server.headers != { }) { inherit (server) headers; }
    else
      {
        type = "stdio";
        inherit (server) command;
      }
      // lib.optionalAttrs (server.args != [ ]) { inherit (server) args; }
      // lib.optionalAttrs (server.env != { }) { inherit (server) env; };

  mcpServers = mcpClient.renderServers {
    inherit (config.programs.aiMcp) enabledServers;
    excluded = cfg.excludedMcpServers;
    normalize = normalizeMcpServer;
    client = "cursor";
  };

  # Nix-managed defaults for cli-config.json (schema: version, editor,
  # permissions, approvalMode). Deep-merged over runtime state on activation.
  cliConfig = {
    version = 1;
    inherit (cfg) approvalMode;
    editor.vimMode = cfg.vimMode;
    permissions = formatters.cursor.formatPermission permissions;
  };

  cliConfigJson = pkgs.writeText "cursor-cli-config.json" (
    builtins.toJSON (lib.recursiveUpdate cliConfig cfg.extraSettings)
  );
in
{
  imports = [ ./options.nix ];

  # Shadow home-manager 26.05's upstream programs.cursor module — that one is
  # the Cursor IDE (mkVscodeModule: argv.json, extensions, code-cursor
  # package) and would fight this CLI module and nix-darwin's own IDE install
  # for ownership of ~/.cursor/. Same pattern as opencode / antigravity-cli.
  disabledModules = [ "programs/cursor.nix" ];

  config = lib.mkMerge [
    # Read-only introspection option set unconditionally so module evaluation
    # (and the shared MCP renderer-parity check) succeeds even when
    # programs.cursor.enable = false.
    {
      programs.cursor.mcpServerNames = lib.attrNames mcpServers;
    }
    (lib.mkIf cfg.enable {
      home = {
        packages = [ pkgs.cursor-cli ];

        file = {
          ".local/bin/cursor-agent".source = "${pkgs.cursor-cli}/bin/cursor-agent";
          ".local/bin/agent".source = "${pkgs.cursor-cli}/bin/cursor-agent";
          ".cursor/mcp.json".text = builtins.toJSON { inherit mcpServers; };
        };

        activation.cursorConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          export PATH="${pkgs.jq}/bin:$PATH"
          $DRY_RUN_CMD ${../scripts/merge-json-settings.sh} \
            "${cliConfigJson}" \
            "${homeDir}/.cursor/cli-config.json"
        '';
      };
    })
  ];
}
