{
  pkgs,
  mkHmConfig,
  fakePackage,
}:
let
  customConfig = mkHmConfig [
    {
      programs.opencode = {
        enable = true;
        configDir = ".config/custom-opencode";
        package = pkgs.lib.mkForce fakePackage;
      };
    }
  ];
  customLauncher = pkgs.lib.findFirst (
    p: (p.passthru.realPackage or null) == fakePackage
  ) null customConfig.config.home.packages;
  customWall = pkgs.lib.findFirst (
    p: p.passthru ? sandboxProfile
  ) null customConfig.config.home.packages;
  invalidConfigDir =
    path:
    builtins.tryEval
      (mkHmConfig [
        { programs.opencode.configDir = path; }
      ]).config.programs.opencode.configDir;
in
{
  opencode-custom-config-launcher =
    assert customConfig.config.home.file ? ".config/custom-opencode/opencode.json";
    assert customConfig.config.home.file ? ".config/custom-opencode/tui.jsonc";
    assert customConfig.config.home.file ? ".config/custom-opencode/cli.json";
    assert customConfig.config.home.file ? ".config/custom-opencode/plugins/herdr-agent-state.js";
    assert
      customConfig.config.home.sessionVariables.OPENCODE_CONFIG_DIR
      == "${customConfig.config.home.homeDirectory}/.config/custom-opencode";
    assert !(invalidConfigDir "/tmp/config").success;
    assert !(invalidConfigDir "../outside").success;
    assert !(invalidConfigDir ".").success;
    pkgs.runCommand "check-opencode-custom-config-launcher" { } ''
      env -i PATH="$PATH" ${customLauncher}/bin/opencode | \
        grep -Fx '${customConfig.config.home.homeDirectory}/.config/custom-opencode' >/dev/null
      ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
        grep -F '${customConfig.config.home.homeDirectory}/.config/custom-opencode' ${customWall.passthru.sandboxProfile} >/dev/null
      ''}
      touch "$out"
    '';
}
