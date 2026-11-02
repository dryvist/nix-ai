# herdr-hail context and opt-in summarizer settings reach both service renderers.
{ pkgs, hmConfigDarwin }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  expectedContextLines = 40;
  expectedSummarizer = {
    enabled = true;
    baseUrl = "http://127.0.0.1:11434/v1";
    model = "fast";
    timeoutMs = 750;
    maxInputChars = 4000;
  };

  darwin = hmConfigDarwin.config.services.herdr.hail.renderedSettings;
  darwinEnabled =
    (hmConfigDarwin.extendModules {
      modules = [
        {
          services.herdr.hail.summarizer = {
            enable = true;
            inherit (expectedSummarizer)
              baseUrl
              model
              timeoutMs
              maxInputChars
              ;
          };
        }
      ];
    }).config.services.herdr.hail.renderedSettings;
  baseUrlRejected =
    value:
    !(builtins.tryEval (
      builtins.deepSeq
        (hmConfigDarwin.extendModules {
          modules = [
            {
              services.herdr.hail.summarizer.baseUrl = value;
            }
          ];
        }).config.services.herdr.hail.renderedSettings
        true
    )).success;
  unsafeBaseUrlsRejected = lib.all baseUrlRejected [
    "https://example.test/v1"
    "http://localhost.evil.test/v1"
    "http://localhost:11434@evil.test/v1"
  ];

  evalNixos =
    summarizer:
    (lib.evalModules {
      specialArgs = {
        inherit pkgs;
        herdr-hail-src = null;
      };
      modules = [
        ../../modules/herdr/hail.nix
        {
          # Stand-ins for NixOS options the unit also writes to; only renderedSettings is forced.
          options = {
            assertions = lib.mkOption {
              type = lib.types.listOf lib.types.raw;
              default = [ ];
            };
            environment = lib.mkOption {
              type = lib.types.raw;
              default = { };
            };
            systemd = lib.mkOption {
              type = lib.types.raw;
              default = { };
            };
            services.herdr = {
              enable = lib.mkOption { type = lib.types.bool; };
              user = lib.mkOption { type = lib.types.str; };
              stateDir = lib.mkOption { type = lib.types.str; };
              socketPath = lib.mkOption { type = lib.types.str; };
              onFailureUnit = lib.mkOption { type = lib.types.nullOr lib.types.str; };
            };
          };
          config.services.herdr = {
            enable = true;
            user = "herdr";
            stateDir = "/var/lib/herdr";
            socketPath = "/run/herdr/herdr.sock";
            onFailureUnit = null;
            hail.enable = true;
            hail.summarizer = summarizer;
          };
        }
      ];
    }).config.services.herdr.hail.renderedSettings;

  nixos = evalNixos { };
  nixosEnabled = evalNixos {
    enable = true;
    inherit (expectedSummarizer)
      baseUrl
      model
      timeoutMs
      maxInputChars
      ;
  };
in
{
  herdr-hail-context-regression =
    assert builtins.deepSeq darwin (
      builtins.deepSeq darwinEnabled (builtins.deepSeq nixos (builtins.deepSeq nixosEnabled true))
    );
    assert lib.assertMsg (darwin.contextLines == expectedContextLines)
      "herdr-hail LaunchAgent renders contextLines ${toString darwin.contextLines}, expected ${toString expectedContextLines}";
    assert lib.assertMsg (nixos.contextLines == expectedContextLines)
      "herdr-hail NixOS unit renders contextLines ${toString nixos.contextLines}, expected ${toString expectedContextLines}";
    assert lib.assertMsg (
      !darwin.summarizer.enabled && !nixos.summarizer.enabled
    ) "herdr-hail summarizer must default disabled on Darwin and NixOS";
    assert lib.assertMsg (
      darwinEnabled.summarizer == expectedSummarizer
    ) "herdr-hail LaunchAgent did not render the configured summarizer settings";
    assert lib.assertMsg (
      nixosEnabled.summarizer == expectedSummarizer
    ) "herdr-hail NixOS unit did not render the configured summarizer settings";
    assert lib.assertMsg unsafeBaseUrlsRejected
      "herdr-hail must reject non-loopback summarizer baseUrls at configuration time";
    helpers.mkMarker "check-herdr-hail-context-regression" "herdr-hail renders bounded context and opt-in summarizer settings on Darwin and NixOS.";
}
