# herdr module regression tests
#
# The coverage check is the load-bearing one. herdr classifies a pane as
# working/blocked/idle by matching manifest rules against the foreground
# process. Without a manifest, downstream consumers see a bare shell.
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

  # Herdr selects local manifests by filename, so translate nix-ai option names
  # to Herdr's names. knownUpstreamAgents remains keyed by nix-ai option name.
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
// (import ./herdr-integrations.nix { inherit pkgs hmConfig; })
// (import ./herdr-services.nix { inherit pkgs hmConfigDarwin; })
// (import ./herdr-claude-hooks.nix { inherit pkgs hmConfig; })
