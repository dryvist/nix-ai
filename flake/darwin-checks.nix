# Focused macOS module checks for native agent launchers.
# Kept separately so the full x86_64-linux regression suite remains Linux-only.
{
  nixpkgs,
  home-manager,
  aiModule,
  src,
}:
let
  system = "aarch64-darwin";
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  fixtures = import (src + "/lib/checks-fixtures.nix") {
    inherit pkgs home-manager aiModule;
  };
  hmConfig = fixtures.mkHmConfig [ { programs.ai.untrustedClis.enable = true; } ];
  hmConfigDarwinHerdr = fixtures.mkHmConfig [
    {
      programs.herdr.enable = true;
      services.herdr.hail = {
        enable = true;
        launchPrefix = [
          "runtime-secret-launcher"
          "run"
          "--"
        ];
        settings.slack.enabled = true;
      };
    }
  ];
in
{
  ${system} =
    (import (src + "/lib/checks/opencode.nix") { inherit pkgs hmConfig; })
    // (import (src + "/lib/checks/herdr.nix") {
      inherit pkgs hmConfig;
      hmConfigDarwin = hmConfigDarwinHerdr;
    })
    // (import (src + "/lib/checks/herdr-settings.nix") { inherit pkgs hmConfig; })
    // (import (src + "/lib/checks/opencode-trusted.nix") {
      inherit pkgs hmConfig;
      inherit (fixtures) mkHmConfig;
    })
    // (import (src + "/lib/checks/qwen-code.nix") {
      inherit pkgs hmConfig;
      inherit (fixtures)
        hmConfigLitellmLocal
        hmConfigQwenRouter
        hmConfigQwenMissingResident
        hmConfigStaticServing
        ;
    })
    // (import (src + "/lib/checks/opencode-sandbox.nix") { inherit pkgs; })
    // (import (src + "/lib/checks/qwen-code-sandbox.nix") {
      inherit pkgs;
      inherit (fixtures) hmConfigLitellmLocal hmConfigQwenRouter;
      hmConfig = fixtures.hmConfigStaticServing;
    });
}
