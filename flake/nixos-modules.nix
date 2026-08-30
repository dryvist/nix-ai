# NixOS modules exported by nix-ai.
#
# nix-ai has historically exported home-manager modules only, because
# everything it managed ran on one Mac under launchd. herdr is the first thing
# that also has to run as a service on a Linux guest, so this is where the
# system-level half lives.
#
# Same wrapper shape as flake/home-manager-modules.nix: flake inputs reach
# modules through `_module.args`, never as function parameters.
{
  llm-agents,
}:
{
  herdr = {
    imports = [ ../modules/herdr/nixos.nix ];
    _module.args = {
      inherit llm-agents;
    };
  };
}
