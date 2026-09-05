# OpenCode Module
#
# Binary from nixpkgs; config declarative. OpenCode never
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
  llm-agents,
  ...
}:

let
  cfg = config.programs.opencode;
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
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
    # One subagent per router role, so the delegation skills that address a
    # tier by role name (`@subagent`, `@judge`, `@cheap`; `lead` for a
    # deliberate hand-off) work here as they do elsewhere. Each is pinned to
    # its own `litellm/<role>` model rather than inheriting the caller's, which
    # is the whole point of a tier. Permissions stay the global defaults.
    agent = lib.genAttrs litellmRoles (role: {
      description = "Delegate to the router's `${role}` tier (resolved upstream, never a physical model)";
      mode = "subagent";
      model = "litellm/${role}";
    });
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
      # llm-agents.nix packages opencode for both supported systems, so the
      # binary is no longer "installed out-of-band" — that gap is why a Linux
      # host got config with nothing to run it.
      #
      # Sourced from llm-agents rather than nixpkgs because it tracks upstream
      # far more closely (1.18.29 against 26.05's 1.15.10). Unlike codex there
      # is no Homebrew cask involved: one owner on every platform.
      programs.opencode.package = lib.mkDefault llmAgents.opencode;

      home = {
        packages = lib.optional (cfg.package != null) cfg.package;

        file = {
          "${configDir}/opencode.json".source = settingsJson;
        }
        // lib.foldl' (acc: dir: acc // mkCommandLinks dir) { } cfg.commandDirs;
      };
    })
  ];
}
