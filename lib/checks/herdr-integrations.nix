{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.herdr;
  programs = hmConfig.config.programs;
  opencodeDir = programs.opencode.configDir or ".config/opencode";
in
{
  # Verify contributed events and assets; the owner-rendered JSON is checked below.
  herdr-integrations-regression =
    let
      files = hmConfig.config.home.file;
      enabledIntegrations = lib.attrNames (lib.filterAttrs (_: value: value.enable) cfg.integrations);
      claudeHooks = hmConfig.config.programs.claude.hooks.events or { };
      sessionStart = claudeHooks.SessionStart or [ ];
      commands = lib.concatMap (entry: map (h: h.command or "") (entry.hooks or [ ])) sessionStart;
      declaresHerdr = lib.any (c: lib.hasInfix "herdr-agent-state.sh" c) commands;

      expectedFiles = {
        claude = [ ".claude/hooks/herdr-agent-state.sh" ];
        codex = [
          ".codex/herdr-agent-state.sh"
          ".codex/hooks.json"
        ];
        antigravity-cli = [
          "${programs.antigravity-cli.nativeConfigDir}/hooks/herdr-agent-state.sh"
          "${programs.antigravity-cli.nativeConfigDir}/hooks.json"
        ];
        copilot = [
          ".copilot/hooks/herdr-agent-state.sh"
          ".copilot/settings.json"
        ];
        opencode = [
          "${opencodeDir}/plugins/herdr-agent-state.js"
          "${opencodeDir}/herdr-tui-session.js"
          "${opencodeDir}/tui.jsonc"
          "${opencodeDir}/herdr-opencode/tui.js"
          "${opencodeDir}/cli.json"
        ];
      };

      missing = lib.concatMap (
        target: lib.filter (f: !(lib.hasAttr f files)) (expectedFiles.${target} or [ ])
      ) (lib.attrNames (lib.filterAttrs (_: value: value.enable) cfg.integrations));

      problems =
        lib.optional (missing != [ ])
          "declares integrations ${lib.concatStringsSep ", " enabledIntegrations} but does not render: ${lib.concatStringsSep ", " missing}"
        ++ lib.optional (
          cfg.integrations.claude.enable && !declaresHerdr
        ) "claude integration renders its hook but never registers it in hooks.events.SessionStart";
    in
    assert lib.assertMsg (problems == [ ]) ''
      herdr integrations are misdeclared:
      ${lib.concatMapStringsSep "\n" (p: "  - ${p}") problems}
    '';
    assert builtins.deepSeq (map (f: "${files.${f}.source}") (
      lib.concatMap (t: expectedFiles.${t} or [ ]) enabledIntegrations
    )) true;
    helpers.mkMarker "check-herdr-integrations-regression" "herdr lifecycle hooks render and register for ${
      if enabledIntegrations == [ ] then "no agents" else lib.concatStringsSep ", " enabledIntegrations
    }.";

  herdr-owner-composition-regression =
    let
      extended =
        (hmConfig.extendModules {
          modules = [
            {
              programs = {
                ai.untrustedClis.enable = true;
                antigravity-cli.nativeConfigDir = ".config/custom-agy";
                opencode = {
                  tuiSettings.plugin = [ "existing-tui" ];
                  cliSettings.plugins = [ "existing-cli" ];
                };
                qwen-code.extraSettings.hooks.SessionStart = [ { hooks = [ { command = "existing-qwen"; } ]; } ];
                copilot-cli.nativeHooks.SessionStart = [
                  {
                    type = "command";
                    bash = "existing-copilot";
                  }
                ];
              };
            }
          ];
        }).config;
      inherit (extended) programs;
      files = extended.home.file;
      agyCommand = (builtins.head programs.antigravity-cli.nativeHooks.herdr.PreInvocation).command;
    in
    assert lib.elem "existing-tui" programs.opencode.tuiSettings.plugin;
    assert lib.elem "./herdr-tui-session.js" programs.opencode.tuiSettings.plugin;
    assert lib.elem "existing-cli" programs.opencode.cliSettings.plugins;
    assert lib.elem "./herdr-opencode" programs.opencode.cliSettings.plugins;
    assert lib.hasAttr ".config/custom-agy/hooks/herdr-agent-state.sh" files;
    assert lib.hasInfix "/.config/custom-agy/hooks/herdr-agent-state.sh" agyCommand;
    assert builtins.length programs.copilot-cli.nativeHooks.SessionStart == 2;
    assert
      (builtins.head programs.qwen-code.generatedSettings.hooks.SessionStart).hooks
      == [ { command = "existing-qwen"; } ];
    assert programs.qwen-code.nativeHooks ? SessionStart;
    assert lib.hasAttr ".qwen/extensions/nix-ai-hooks/qwen-extension.json" files;
    assert lib.hasAttr ".qwen/hooks/herdr-agent-session.sh" files;
    helpers.mkMarker "check-herdr-owner-composition-regression" "Existing app hooks and plugin registrations coexist with Herdr.";

}
