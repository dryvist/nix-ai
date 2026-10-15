# Qwen Code built-in tool exclusions stay additive to shared permissions.
{
  pkgs,
  hmConfigQwenRouter,
  hmConfigStaticServing,
  hmConfigQwenExcludeToolsEmpty,
  hmConfigQwenExcludeToolsCustom,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  settingsOf = hm: hm.config.programs.qwen-code.generatedSettings;
  routerSettings = settingsOf hmConfigQwenRouter;
  bySizeSettings = settingsOf hmConfigStaticServing;
  emptySettings = settingsOf hmConfigQwenExcludeToolsEmpty;
  customSettings = settingsOf hmConfigQwenExcludeToolsCustom;

  # excludeTools = [ ] leaves the shared formatter's deny list as is, so the
  # empty fixture is the baseline every other fixture must extend.
  baseDeny = emptySettings.permissions.deny;
  baseAllow = emptySettings.permissions.allow;
  defaultTools = [
    "skill"
    "todo_write"
    "agent"
    "ask_user_question"
  ];
in
{
  qwen-code-exclude-tools-regression = helpers.mkDefaultsRegression {
    label = "Qwen Code excluded built-in tools";
    checkName = "check-qwen-code-exclude-tools-regression";
    checks = [
      {
        name = "default option list";
        actual = hmConfigQwenRouter.config.programs.qwen-code.excludeTools;
        expected = defaultTools;
      }
      {
        name = "empty option adds none of the default tools to the baseline deny list";
        actual = builtins.filter (tool: builtins.elem tool baseDeny) defaultTools;
        expected = [ ];
      }
      {
        name = "router-only host appends the default tools after every baseline entry";
        actual = routerSettings.permissions.deny;
        expected = baseDeny ++ defaultTools;
      }
      {
        name = "by-size host appends the default tools after every baseline entry";
        actual = bySizeSettings.permissions.deny;
        expected = baseDeny ++ defaultTools;
      }
      {
        name = "custom collision entry is already in the baseline deny list";
        actual = builtins.elem "Bash(diskutil eraseDisk *)" baseDeny;
        expected = true;
      }
      {
        name = "custom list passes through once and skips an existing deny rule";
        actual = customSettings.permissions.deny;
        expected = baseDeny ++ [ "custom_tool" ];
      }
      {
        name = "permissions.allow is unchanged for default, by-size, and custom lists";
        actual = [
          routerSettings.permissions.allow
          bySizeSettings.permissions.allow
          customSettings.permissions.allow
        ];
        expected = lib.replicate 3 baseAllow;
      }
    ];
  };
}
