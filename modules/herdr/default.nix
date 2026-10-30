# Hail remains owned by nix-ai while Herdr itself comes from nix-herdr.
{ lib, ... }:
{
  imports = [
    ./hail-options.nix
    ./launchd-hail.nix
  ];

  # Detection coverage is a nix-ai concern: it describes this composition's
  # agent names rather than Herdr's installer targets.
  options.programs.herdr = {
    knownUnsupportedAgents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "cecli" ];
      description = "Enabled agent names without a verified Herdr detection manifest.";
    };
    knownUpstreamAgents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = [
        "antigravity-cli"
        "claude"
        "codex"
        "copilot"
        "cursor"
        "droid"
        "grok"
        "hermes"
        "opencode"
        "pi"
        "qwen-code"
      ];
      description = "nix-ai agent names covered by Herdr's bundled detection manifests.";
    };
  };
}
