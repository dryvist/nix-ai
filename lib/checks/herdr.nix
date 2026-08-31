# herdr module regression tests
#
# The coverage check is the load-bearing one. herdr classifies a pane as
# working/blocked/idle by matching manifest rules against the foreground
# process; a CLI with no manifest shows up as a bare shell, and every downstream
# consumer — the Slack bridge's blocked-agent alerts, `herdr agent wait`, the
# web dashboard's approvals — silently sees nothing to report. Adding a CLI to
# this flake without a manifest is exactly the "a newly advertised tier cannot
# go unmonitored" failure the fabric watchdog's assert exists to prevent.
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.herdr;
  programs = hmConfig.config.programs;

  # Which of this flake's CLIs herdr is expected to recognise, and the manifest
  # name herdr knows each by (its own name, not ours).
  managedAgents = {
    claude = programs.claude.enable or false;
    codex = programs.codex.enable or false;
    cursor = programs.cursor.enable or false;
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
      "configDir"
      "defaultRemote"
      "enable"
      "knownUnsupportedAgents"
      "knownUpstreamAgents"
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
        name = "herdr.configDir";
        actual = cfg.configDir;
        expected = ".config/herdr";
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

  # Forces the rendered config.toml and every manifest, not just their
  # attribute names — a check that reads a few attributes of a large structure
  # proves nothing about the rest (see CLAUDE.md).
  herdr-rendered-files-regression =
    let
      files = hmConfig.config.home.file;
      configPath = "${cfg.configDir}/config.toml";
      ours = lib.filterAttrs (name: _: lib.hasPrefix "${cfg.configDir}/" name) files;
    in
    assert lib.hasAttr configPath files || throw "herdr: ${configPath} is not rendered";
    # Force each rendered file's STORE PATH, not the derivation itself.
    # `deepSeq` over a derivation walks its whole attrset — drvAttrs, passthru,
    # every build input — which is both enormously slow and prone to erroring on
    # attributes that were never meant to be forced. Interpolating to a string
    # forces exactly what this check is about: that every file under configDir
    # actually renders to a path.
    assert builtins.deepSeq (lib.mapAttrsToList (_: f: "${f.source}") ours) true;
    helpers.mkMarker "check-herdr-rendered-files-regression" "herdr renders ${toString (lib.length (lib.attrNames ours))} file(s) under ${cfg.configDir}.";

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
