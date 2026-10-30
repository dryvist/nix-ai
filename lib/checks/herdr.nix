# herdr module regression tests
#
# The coverage check is the load-bearing one. herdr classifies a pane as
# working/blocked/idle by matching manifest rules against the foreground
# process; a CLI with no manifest shows up as a bare shell, and every downstream
# consumer — blocked-agent alerting, `herdr agent wait`, the web dashboard's
# approvals — silently sees nothing to report. Adding a CLI to
# this flake without a manifest is exactly the "a newly advertised tier cannot
# go unmonitored" failure the fabric watchdog's assert exists to prevent.
{
  pkgs,
  hmConfig,
  hmConfigDarwin,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.herdr;
  programs = hmConfig.config.programs;
  opencodeDir = programs.opencode.configDir or ".config/opencode";

  # Which of this flake's CLIs herdr is expected to recognise, keyed by THIS
  # flake's option name. Translation to herdr's own manifest name happens in
  # `covered` below, and only for the agentManifests branch.
  managedAgents = {
    claude = programs.claude.enable or false;
    codex = programs.codex.enable or false;
    opencode = programs.opencode.enable or false;
    antigravity-cli = programs.antigravity-cli.enable or false;
    qwen-code = programs.qwen-code.enable or false;
    cecli = programs.cecli.enable or false;
  };

  enabledAgents = lib.attrNames (lib.filterAttrs (_: v: v) managedAgents);

  # herdr selects a local manifest by FILENAME, and agentManifests renders
  # `<attrname>.toml`. So a manifest must be keyed by HERDR's name for the
  # agent, not by this flake's option name: `agentManifests.qwen-code` writes
  # qwen-code.toml, which herdr ignores without warning while still looking
  # like coverage here. Verified live against 0.8.2 — an identical manifest is
  # picked up as `source_kind: local override` under qwen.toml and produces no
  # local override, and no diagnostic, under any other filename.
  #
  # Only this branch needs the translation. knownUpstreamAgents is keyed by
  # option name on purpose, because it answers "is the CLI we enable detected",
  # not "what is the file called".
  herdrManifestName = {
    antigravity-cli = "agy";
    qwen-code = "qwen";
  };

  covered =
    name:
    lib.elem name cfg.knownUpstreamAgents
    || lib.hasAttr (herdrManifestName.${name} or name) cfg.agentManifests
    || lib.elem name cfg.knownUnsupportedAgents;

  uncovered = lib.filter (name: !(covered name)) enabledAgents;
in
{
  herdr-options-regression = helpers.mkOptionsRegression {
    label = "herdr";
    checkName = "check-herdr-options-regression";
    inherit cfg;
    expectedOptions = [
      "agentManifests"
      "defaultRemote"
      "enable"
      "integrations"
      "knownUnsupportedAgents"
      "knownUpstreamAgents"
      "server"
      "package"
      "remotes"
      "settings"
    ];
  };

  herdr-defaults-regression = helpers.mkDefaultsRegression {
    label = "herdr";
    checkName = "check-herdr-defaults-regression";
    checks = [
      {
        name = "herdr.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "herdr.server.enable";
        actual = cfg.server.enable;
        expected = true;
      }
      {
        name = "herdr.package is installed (not null)";
        actual = cfg.package != null;
        expected = true;
      }
      {
        name = "herdr binary lands in home.packages";
        actual = lib.elem cfg.package hmConfig.config.home.packages;
        expected = true;
      }
    ];
  };

  # Forces every linked config file and manifest, not just their attribute
  # names — a check that reads a few attributes of a large structure proves
  # nothing about the rest (see CLAUDE.md).
  herdr-rendered-files-regression =
    let
      files = hmConfig.config.home.file;
      configDir = "${hmConfig.config.xdg.configHome}/herdr";
      ours = lib.filterAttrs (name: _: lib.hasPrefix "${configDir}/" name) files;
      configFiles = lib.filterAttrs (name: _: lib.hasPrefix "herdr/" name) hmConfig.config.xdg.configFile;
    in
    # Force each rendered file's STORE PATH, not the derivation itself.
    # `deepSeq` over a derivation walks its whole attrset — drvAttrs, passthru,
    # every build input — which is both enormously slow and prone to erroring on
    # attributes that were never meant to be forced. Interpolating to a string
    # forces exactly what this check is about: that every managed Herdr file
    # actually renders to a path.
    assert builtins.deepSeq (lib.mapAttrsToList (_: f: "${f.source}") ours) true;
    assert builtins.deepSeq (lib.mapAttrsToList (_: f: "${f.source}") configFiles) true;
    helpers.mkMarker "check-herdr-rendered-files-regression" "herdr managed files render under ${configDir}.";

  # The TUI is a client, so a module that installs the binary and renders
  # config.toml without declaring a service yields no running herd at all —
  # invisible in the rendered config and raising no error anywhere.
  herdr-launchd-regression =
    let
      agents = hmConfigDarwin.config.launchd.agents;
      absent = throw "herdr: no launchd agent is declared, so the server never runs and the herd stays empty; see nix-herdr user server module";
      agent = (agents.herdr or absent).config;
      args = agent.ProgramArguments;
      env = agent.EnvironmentVariables or { };
      expectedSocket = "${hmConfigDarwin.config.xdg.configHome}/herdr/herdr.sock";
      profileBin = "/etc/profiles/per-user/${hmConfigDarwin.config.home.username}/bin";
      pathEntries = lib.splitString ":" (env.PATH or "");

      # Collected rather than asserted one at a time, so a broken agent reports
      # every fault in one pass. The last two are the silent ones: a mismatched
      # socket leaves the client hunting a socket nothing created, and a PATH
      # without the Nix profile makes every pane look like a bare shell.
      problems =
        lib.optional (
          !(lib.elem "server" args)
        ) "must run the headless server (`herdr server`), got: ${builtins.concatStringsSep " " args}"
        ++ lib.optional (!(agent.KeepAlive or false)) "must set KeepAlive = true"
        ++ lib.optional (!(agent.RunAtLoad or false)) "must set RunAtLoad = true"
        ++ lib.optional ((agent.ProcessType or "") != "Background") ''must set ProcessType = "Background"''
        ++
          lib.optional ((env.HERDR_SOCKET_PATH or null) != expectedSocket)
            "must pin HERDR_SOCKET_PATH to ${expectedSocket}, keeping the server's socket and the client's identical"
        ++ lib.optional (
          !(lib.elem profileBin pathEntries)
        ) "PATH must include ${profileBin}, leaving panes able to run claude/codex";
    in
    assert lib.assertMsg (problems == [ ]) ''
      herdr LaunchAgent is misdeclared:
      ${lib.concatMapStringsSep "\n" (p: "  - ${p}") problems}
    '';
    # Force the whole agent, not just the attributes read above.
    assert builtins.deepSeq agents true;
    helpers.mkMarker "check-herdr-launchd-regression" "herdr LaunchAgent runs the headless server with a pinned socket and a Nix-profile PATH.";

  herdr-hail-darwin-eval =
    let
      cfg = hmConfigDarwin.config;
      hail = cfg.services.herdr.hail;
      agent = cfg.launchd.agents.herdr-hail.config;
      env = agent.EnvironmentVariables;
      prefix = [
        "runtime-secret-launcher"
        "run"
        "--"
      ];
    in
    assert hail.launchPrefix == prefix;
    assert agent.ProgramArguments == prefix ++ [ (lib.getExe hail.package) ];
    assert agent.KeepAlive && agent.RunAtLoad;
    assert env.HERDR_SOCKET_PATH == "${cfg.xdg.configHome}/herdr/herdr.sock";
    assert lib.hasSuffix "/herdr-hail-config" env.HERDR_PLUGIN_CONFIG_DIR;
    assert hail.settings.slack.enabled;
    assert lib.all (name: !(lib.hasAttr name env)) [
      "SLACK_BOT_TOKEN"
      "SLACK_APP_TOKEN"
      "DISCORD_BOT_TOKEN"
    ];
    helpers.mkMarker "check-herdr-hail-darwin-eval" "herdr Hail Darwin LaunchAgent and runtime argument prefix evaluated.";

  # Verify contributed events and assets; the owner-rendered JSON is checked below.
  herdr-integrations-regression =
    let
      files = hmConfig.config.home.file;
      enabledIntegrations = lib.attrNames (lib.filterAttrs (_: value: value.enable) cfg.integrations);
      claudeHooks = hmConfig.config.programs.claude.settings.hooks or { };
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
        ) "claude integration renders its hook but never registers it in settings.hooks.SessionStart";
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

  # Inspect the owner-generated JSON at build time, avoiding import-from-derivation.
  herdr-claude-rendered-hooks =
    let
      composed = hmConfig.extendModules {
        modules = [
          {
            programs.claude.hooks = {
              sessionStart = lib.mkForce "printf typed-start";
              refreshMarketplaces = lib.mkForce true;
            };
          }
          {
            programs.claude.settings.hooks.SessionStart = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "fixture-caller-one";
                  }
                ];
              }
            ];
          }
          {
            programs.claude.settings.hooks.SessionStart = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "fixture-caller-two";
                  }
                ];
              }
            ];
          }
        ];
      };
    in
    pkgs.runCommand "check-herdr-claude-rendered-hooks" { nativeBuildInputs = [ pkgs.jq ]; } ''
      set -euo pipefail
      settings_json=$(grep -o '/nix/store/[a-z0-9]*-claude-settings\.json' ${composed.activationPackage}/activate | head -1)
      jq -e '
        [.hooks.SessionStart[]?.hooks[]?.command | select(type == "string")] as $commands |
        ($commands | map(select(contains("herdr-agent-state.sh"))) | length) == 1 and
        ($commands | map(select(contains("session-start.sh"))) | length) == 1 and
        ($commands | map(select(. == "fixture-caller-one")) | length) == 1 and
        ($commands | map(select(. == "fixture-caller-two")) | length) == 1 and
        any(.hooks.SessionStart[]?.hooks[]?; (.command // "" | contains("session-start.sh")) and .async == true and .timeout == 300)
      ' "$settings_json" >/dev/null
      touch "$out"
    '';

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

  herdr-agent-coverage-regression =
    assert
      uncovered == [ ]
      || throw ''
        herdr agent-detection coverage gap: ${lib.concatStringsSep ", " uncovered}

        These CLIs are enabled in this flake but herdr has no manifest for them,
        so their panes will show no working/blocked/idle state and nothing
        downstream (Slack alerts, `herdr agent wait`, dashboard approvals) will
        fire for them.

        Fix by adding an entry to programs.herdr.agentManifests. Author it
        against `herdr agent explain <target> --json` on a live pane — the rule
        schema is herdr's, so do not guess it. If the gap is deliberate for
        now, name it in programs.herdr.knownUnsupportedAgents instead, which
        makes it reviewable rather than invisible.
      '';
    helpers.mkMarker "check-herdr-agent-coverage-regression" "herdr detection covers all ${toString (lib.length enabledAgents)} enabled agent CLIs.";
}
