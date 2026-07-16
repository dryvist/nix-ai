# OpenCode Module
#
# Config-only (binary installed out-of-band, like qwen-code). OpenCode never
# rewrites its global config — state lives in ~/.local/share/opencode — so
# opencode.json is a plain declarative home.file, no deep-merge activation.
#
# Skills arrive via the shared agent-skills registry
# (modules/agent-skills/harnesses.nix -> ~/.config/opencode/skills symlink).
# Commands are linked per-file from commandDirs so future sources coexist.
{
  config,
  lib,
  nix-claude-code,
  ...
}:

let
  cfg = config.programs.opencode;

  aiCommon = import ../common { inherit lib config nix-claude-code; };
  permission = aiCommon.formatters.opencode.formatPermission aiCommon.permissions;

  mcpClient = import ../mcp/client.nix { inherit lib; };

  # opencode.json uses a local/remote-tagged MCP schema: local servers carry a
  # single `command` array (argv0 included) and `environment`; remote servers
  # carry `url` and optional `headers`. `enabled` defaults true, so it is
  # omitted. Verified against https://opencode.ai/config.json.
  normalizeMcpServer =
    server:
    if server.url != null then
      {
        type = "remote";
        inherit (server) url;
      }
      // lib.optionalAttrs (server.headers != { }) { inherit (server) headers; }
    else
      {
        type = "local";
        command = [ server.command ] ++ server.args;
      }
      // lib.optionalAttrs (server.env != { }) { environment = server.env; };

  mcpServers = mcpClient.renderServers {
    inherit (config.programs.aiMcp) enabledServers;
    excluded = cfg.excludedMcpServers;
    normalize = normalizeMcpServer;
  };

  settings = {
    "$schema" = "https://opencode.ai/config.json";
    inherit permission;
    mcp = mcpServers;
  };

  mdFiles =
    dir:
    lib.optionalAttrs (builtins.pathExists dir) (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (builtins.readDir dir)
    );

  mkCommandLinks =
    dir:
    lib.mapAttrs' (name: _: {
      name = ".config/opencode/command/${name}";
      value = {
        source = "${dir}/${name}";
      };
    }) (mdFiles dir);
in
{
  imports = [ ./options.nix ];

  # Shadow home-manager 26.05's upstream programs.opencode module — this
  # module owns the option namespace (same pattern as antigravity-cli).
  disabledModules = [ "programs/opencode.nix" ];

  config = lib.mkMerge [
    # Read-only introspection option set unconditionally so module evaluation
    # (and the shared MCP renderer-parity check) succeeds even when
    # programs.opencode.enable = false.
    {
      programs.opencode.mcpServerNames = lib.attrNames mcpServers;
    }
    (lib.mkIf cfg.enable {
      home.file = {
        ".config/opencode/opencode.json".text = builtins.toJSON (
          lib.recursiveUpdate settings cfg.extraSettings
        );
      }
      // lib.foldl' (acc: dir: acc // mkCommandLinks dir) { } cfg.commandDirs;
    })
  ];
}
