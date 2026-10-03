# oh-my-openagent switch (programs.ai.ohMyOpenagent.disabled, default true).
#
# Default: no plugin entry in the OpenCode settings and no omo-senpi wrapper.
# disabled = false: the plugin entry appears, and omo-senpi appears when the
# untrusted CLI gate is also on. The enabled half keeps the default
# assertions from passing vacuously on a renamed plugin or wrapper.
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
        name = "default: programs.ai.ohMyOpenagent.disabled";
        actual = hmConfig.config.programs.ai.ohMyOpenagent.disabled;
        expected = true;
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
        name = "disabled = false: omo-senpi installed";
        actual = hasWrapper hmConfigOhMyOpenagent;
        expected = true;
      }
      {
        name = "disabled = false: plugin entry";
        actual = pluginEntries hmConfigOhMyOpenagent;
        expected = entry;
      }
      {
        # omo-senpi is an untrusted CLI, so clearing `disabled` alone never installs it.
        name = "disabled = false without the untrusted gate: omo-senpi installed";
        actual = hasWrapper hmConfigOhMyOpenagentTrusted;
        expected = false;
      }
      {
        name = "disabled = false without the untrusted gate: plugin entry";
        actual = pluginEntries hmConfigOhMyOpenagentTrusted;
        expected = entry;
      }
    ];
  };
}
