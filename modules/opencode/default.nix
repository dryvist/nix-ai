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
  pkgs,
  config,
  lib,
  nix-claude-code,
  ...
}:

let
  cfg = config.programs.opencode;
  inherit (cfg) configDir;
  inherit (config.programs) litellmLocal;

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
    client = "opencode";
  };

  # Role aliases the local proxy serves. Each is a stable name; which physical
  # model it resolves to is an upstream setting, so this list does not change
  # when the mapping does.
  litellmRoles = [
    "lead"
    "subagent"
    "judge"
    "cheap"
  ];

  settings = {
    "$schema" = "https://opencode.ai/config.json";
    inherit permission;
    mcp = mcpServers;
  }
  # The primary agent's model is deliberately NOT set: it stays whatever the
  # user has chosen. Only the cheap background tier is repointed, plus the
  # provider itself so `litellm/<role>` is selectable per agent.
  // lib.optionalAttrs litellmLocal.enable {
    provider.litellm = {
      npm = "@ai-sdk/openai-compatible";
      name = "LiteLLM (local)";
      options = {
        baseURL = litellmLocal.baseUrl;
        apiKey = "{env:LITELLM_LOCAL_KEY}";
      };
      models = lib.genAttrs litellmRoles (role: {
        name = role;
      });
    };
    small_model = "litellm/cheap";
  };

  # Pretty-printed via jq (same convention as copilot.nix / antigravity-cli):
  # builtins.toJSON is compact, so a runCommand + jq '.' derivation produces the
  # human-readable layout the other harness configs use.
  settingsJson =
    pkgs.runCommand "opencode.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        json = builtins.toJSON (lib.recursiveUpdate settings cfg.extraSettings);
        passAsFile = [ "json" ];
      }
      ''
        jq '.' "$jsonPath" > $out
      '';

  mdFiles =
    dir:
    lib.optionalAttrs (builtins.pathExists dir) (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (builtins.readDir dir)
    );

  mkCommandLinks =
    dir:
    lib.mapAttrs' (name: _: {
      name = "${configDir}/command/${name}";
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
        "${configDir}/opencode.json".source = settingsJson;
      }
      // lib.foldl' (acc: dir: acc // mkCommandLinks dir) { } cfg.commandDirs;
    })
  ];
}
