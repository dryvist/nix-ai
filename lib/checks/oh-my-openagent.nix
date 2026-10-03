# oh-my-openagent opt-in (programs.ai.ohMyOpenagent.enable).
#
# Default: no plugin entry in the OpenCode settings and no omo-senpi wrapper.
# Enabled: the plugin entry appears, and omo-senpi appears when the untrusted
# CLI gate is also on. The enabled half keeps the default-off assertions from
# passing vacuously on a renamed plugin or wrapper.
{
  pkgs,
  hmConfig,
  hmConfigUntrusted,
  hmConfigOhMyOpenagent,
  hmConfigOhMyOpenagentTrusted,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;

  hasWrapper = hm: lib.elem "omo-senpi" (map lib.getName hm.config.home.packages);
  pluginEntries = hm: hm.config.programs.opencode.extraSettings.plugin or [ ];
  entry = [ "oh-my-openagent@latest" ];
in
{
  oh-my-openagent-opt-in = helpers.mkDefaultsRegression {
    label = "oh-my-openagent opt-in";
    checkName = "check-oh-my-openagent-opt-in";
    checks = [
      {
        name = "default: programs.ai.ohMyOpenagent.enable";
        actual = hmConfig.config.programs.ai.ohMyOpenagent.enable;
        expected = false;
      }
      {
        name = "default: omo-senpi installed";
        actual = hasWrapper hmConfig;
        expected = false;
      }
      {
        name = "default: plugin entry";
        actual = pluginEntries hmConfig;
        expected = [ ];
      }
      {
        name = "untrusted gate alone: omo-senpi installed";
        actual = hasWrapper hmConfigUntrusted;
        expected = false;
      }
      {
        name = "untrusted gate alone: plugin entry";
        actual = pluginEntries hmConfigUntrusted;
        expected = [ ];
      }
      {
        name = "enabled: omo-senpi installed";
        actual = hasWrapper hmConfigOhMyOpenagent;
        expected = true;
      }
      {
        name = "enabled: plugin entry";
        actual = pluginEntries hmConfigOhMyOpenagent;
        expected = entry;
      }
      {
        # omo-senpi is an untrusted CLI, so the opt-in alone never installs it.
        name = "enabled without the untrusted gate: omo-senpi installed";
        actual = hasWrapper hmConfigOhMyOpenagentTrusted;
        expected = false;
      }
      {
        name = "enabled without the untrusted gate: plugin entry";
        actual = pluginEntries hmConfigOhMyOpenagentTrusted;
        expected = entry;
      }
    ];
  };
}
