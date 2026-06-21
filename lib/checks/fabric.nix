# Fabric module regression tests
#
# Mirrors lib/checks/mlx.nix patterns. Catches silent option/default drift
# and validates the synthetic fabric-patterns marketplace builds correctly.
{
  pkgs,
  hmConfig,
  hmConfigFabricServer,
  src,
}:
let
  cfg = hmConfig.config.programs.fabric;
in
{
  # Verify all expected fabric option paths exist. Note: patternsDir is NOT
  # an option — it is a computed constant in packages.nix (see that file for
  # rationale). This check also asserts patternsDir is NOT in the option set.
  fabric-options-regression =
    let
      expectedOptions = [
        "customPatternsDir"
        "defaultModel"
        "enable"
        "enableServer"
        "host"
        "port"
      ];
      actualOptions = builtins.attrNames cfg;
      missingOptions = builtins.filter (o: !(builtins.elem o actualOptions)) expectedOptions;
      patternsDirIsOption = builtins.elem "patternsDir" actualOptions;
    in
    assert missingOptions == [ ] || throw "Missing fabric options: ${builtins.toJSON missingOptions}";
    assert
      !patternsDirIsOption
      || throw "patternsDir must NOT be a configurable option (it is a computed constant — see modules/fabric/packages.nix)";
    pkgs.runCommand "check-fabric-options-regression" { } ''
      echo "Fabric option regression: ${toString (builtins.length expectedOptions)} options verified"
      touch $out
    '';

  # Verify fabric evaluated config values match expected defaults.
  # Pinning these so accidental drift breaks the build (port collisions, etc.).
  fabric-defaults-regression =
    let
      checks = [
        {
          name = "fabric.enable";
          actual = cfg.enable;
          expected = true;
        }
        {
          name = "fabric.enableServer";
          actual = cfg.enableServer;
          expected = false;
        }
        {
          name = "fabric.host";
          actual = cfg.host;
          expected = "127.0.0.1";
        }
        {
          name = "fabric.port";
          actual = cfg.port;
          expected = 8180;
        }
        {
          name = "fabric.defaultModel";
          actual = cfg.defaultModel;
          expected = "default";
        }
        # Environment variables — FABRIC_PATTERNS_DIR is computed from
        # config.home.homeDirectory + the fixed ".config/fabric/patterns"
        # relative path (see modules/fabric/packages.nix). This check asserts
        # the env var stays in sync with the home.file symlink location.
        {
          name = "fabric.env.FABRIC_PATTERNS_DIR";
          actual = hmConfig.config.home.sessionVariables.FABRIC_PATTERNS_DIR;
          expected = "${hmConfig.config.home.homeDirectory}/.config/fabric/patterns";
        }
        {
          name = "fabric.env.FABRIC_DEFAULT_MODEL";
          actual = hmConfig.config.home.sessionVariables.FABRIC_DEFAULT_MODEL;
          expected = cfg.defaultModel;
        }
      ];
      failures = builtins.filter (c: c.actual != c.expected) checks;
      failureMsg = builtins.concatStringsSep "\n" (
        map (
          c: "  ${c.name}: expected ${builtins.toJSON c.expected}, got ${builtins.toJSON c.actual}"
        ) failures
      );
    in
    assert failures == [ ] || throw "Fabric default value regression:\n${failureMsg}";
    pkgs.runCommand "check-fabric-defaults-regression" { } ''
      echo "Fabric defaults regression: ${toString (builtins.length checks)} critical defaults verified"
      touch $out
    '';

  # Validate the fabric LaunchAgent (positive case): when enableServer = true,
  # ProgramArguments must contain --serve and the configured host:port.
  fabric-launchd =
    let
      serverCfg = hmConfigFabricServer.config.programs.fabric;
      agent = hmConfigFabricServer.config.launchd.agents.fabric.config;
      args = agent.ProgramArguments;
      argsStr = builtins.concatStringsSep " " args;
      expectedAddress = "${serverCfg.host}:${toString serverCfg.port}";
      hasServeFlag = builtins.elem "--serve" args;
      hasAddressFlag = builtins.elem "--address" args;
      hasAddress = builtins.elem expectedAddress args;
      hasKeepAlive = agent.KeepAlive or false;
      hasRunAtLoad = agent.RunAtLoad or false;
      hasBackgroundType = (agent.ProcessType or "") == "Background";
    in
    assert
      hasServeFlag || throw "Fabric LaunchAgent missing --serve flag in ProgramArguments: ${argsStr}";
    assert
      hasAddressFlag || throw "Fabric LaunchAgent missing --address flag in ProgramArguments: ${argsStr}";
    assert
      hasAddress
      || throw "Fabric LaunchAgent missing expected address ${expectedAddress} in ProgramArguments: ${argsStr}";
    assert hasKeepAlive || throw "Fabric LaunchAgent must have KeepAlive = true";
    assert hasRunAtLoad || throw "Fabric LaunchAgent must have RunAtLoad = true";
    assert hasBackgroundType || throw "Fabric LaunchAgent must have ProcessType = \"Background\"";
    pkgs.runCommand "check-fabric-launchd" { } ''
      echo "Fabric LaunchAgent (enableServer=true): --serve --address ${expectedAddress} verified"
      touch $out
    '';

  # Validate the fabric LaunchAgent (negative case): when enableServer = false
  # (the default), no launchd.agents.fabric entry should exist.
  fabric-launchd-negative =
    let
      hasAgent = hmConfig.config.launchd.agents ? fabric;
    in
    assert
      !hasAgent || throw "Fabric LaunchAgent must NOT be defined when enableServer = false (default)";
    pkgs.runCommand "check-fabric-launchd-negative" { } ''
      echo "Fabric LaunchAgent negative: launchd.agents.fabric correctly absent when enableServer = false"
      touch $out
    '';

  # Assert the fabric version in lib/versions.nix matches the version tag of
  # the fabric-src flake input in flake.nix. Renovate's nix manager bumps
  # fabric-src; the customManager regex bumps lib/versions.nix.fabric. The
  # vendorHash only validates the fetched Go source tree — it does NOT detect
  # label drift. This check runs in every `nix flake check`.
  fabric-version-sync =
    let
      flakeSrc = builtins.readFile "${src}/flake.nix";
      versions = import "${src}/lib/versions.nix";
      flakeMatch = builtins.match ".*github:danielmiessler/fabric/v([0-9][^\"]*)\".*" flakeSrc;
    in
    assert pkgs.lib.assertMsg (
      flakeMatch != null
    ) "fabric-version-sync: could not parse fabric-src tag from flake.nix";
    let
      flakeVersion = builtins.elemAt flakeMatch 0;
      pinVersion = versions.fabric or "";
    in
    assert pkgs.lib.assertMsg (
      pinVersion != ""
    ) "fabric-version-sync: lib/versions.nix has no `fabric` entry";
    assert pkgs.lib.assertMsg (flakeVersion == pinVersion)
      "fabric version drift: flake.nix fabric-src=v${flakeVersion} but lib/versions.nix.fabric=${pinVersion}";
    pkgs.runCommand "check-fabric-version-sync" { } ''
      echo "Fabric version sync: flake.nix v${flakeVersion} == lib/versions.nix.fabric ${pinVersion}"
      touch $out
    '';

  # fabric-marketplace-build moved to nix-claude-code/flake/checks.nix as
  # part of PR3 — the synthetic fabric-patterns marketplace derivation and
  # its curated-patterns JSON now live in nix-claude-code.
}
