# Cursor CLI Module
#
# Installs and configures Cursor's terminal coding agent (`agent` /
# `cursor-agent`). The IDE stays installed via nix-darwin
# (home.packages = [ code-cursor ]) — this module only manages the CLI.
#
# Ownership contract ("Nix wins"):
# - Nix owns the CLI binary after every rebuild via home.packages.
# - The profile install puts the binary on PATH.
# - The `~/.local/bin` links exist because the `code-cursor` IDE wrapper
#   and the upstream installer contract both require `agent` and
#   `cursor-agent` at that exact location.
# - Those two links carry `force = true`. The self-updater replaces them with
#   its own real files between activations, and without `force` home-manager
#   refuses to clobber a path it does not own, so activation fails instead of
#   reclaiming the name. `force` makes the linker place them with `ln -Tsf`,
#   which replaces a file or a symlink; `-T` refuses to descend into a
#   directory, so a directory at that path still aborts activation loudly
#   rather than being linked inside.
# - Config ownership is unchanged: mcp.json via home.file + cli-config
#   deep-merge activation.
{
  config,
  lib,
  pkgs,
  nix-claude-code,
  nixpkgs-unstable,
  ...
}:

let
  cfg = config.programs.cursor;
  homeDir = config.home.homeDirectory;

  # Sourced from nixpkgs-unstable, not the 26.05 channel: the release channel
  # froze cursor-cli at 2026.05.16 while upstream ships continuously, and a
  # months-stale agent CLI is not usable. Same reason llama-swap is pulled from
  # unstable in modules/mlx.
  #
  # Imported rather than read off `legacyPackages` because cursor-cli is
  # unfree, and `legacyPackages` carries the stock policy. The consumer's own
  # nixpkgs config is inherited verbatim, so this reuses whatever unfree
  # allowance the consumer already granted for `pkgs.cursor-cli` instead of
  # widening the policy here.
  cursorCli =
    (import nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      inherit (pkgs) config;
    }).cursor-cli;

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
        packages = [ cursorCli ];

        file = {
          ".local/bin/cursor-agent" = {
            source = "${cursorCli}/bin/cursor-agent";
            force = true;
          };
          ".local/bin/agent" = {
            source = "${cursorCli}/bin/cursor-agent";
            force = true;
          };
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
