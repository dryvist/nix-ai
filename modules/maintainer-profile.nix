# Maintainer profile — the single place for every consumer-overridable value.
#
# nix-ai is a reusable module: this file is the one knob surface a consumer
# touches to make the stack their own. Modules read `userConfig` via
# `_module.args` (bound at the bottom), so nothing else needs to import this.
#
# Posture (hybrid):
#   - Identity fields (`user.*`) default to the maintainer's values so derived
#     values (trusted orgs in Claude auto-mode) stay consistent; a consumer
#     overrides `user.fullName`/`user.trustedOrgs`.
#   - One-person infrastructure (`homelab.*`, `telemetry.*`, `extraTrustedPaths`,
#     `trustedProjectDirs`) defaults to clean/off/empty, so this repo ships no
#     personal context and `homeManagerModules.default` evaluates to a neutral
#     config with zero consumer input. The consumer fills these in their own
#     config (e.g. nix-darwin's lib/user-config.nix), for example:
#       homelab = { enable = true; environmentRules = [ "…trusted infra…" ]; };
#       telemetry.enable = true;
#
# Declaring `userConfig` as a typed option gives standalone consumers normal
# merge semantics; binding `_module.args` to it avoids a self-reference cycle
# and stays `mkDefault` so a consumer that injects `_module.args.userConfig`
# directly (as nix-darwin does via extraSpecialArgs) takes precedence.
{ lib, config, ... }:
{
  options.userConfig = lib.mkOption {
    type = lib.types.submodule {
      options = {
        user.fullName = lib.mkOption {
          type = lib.types.str;
          default = "JacobPEvans";
          description = "Full name / GitHub handle used to derive the trusted GitHub org in Claude auto-mode.";
        };

        user.trustedOrgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "dryvist" ];
          description = ''
            Additional GitHub orgs (besides `fullName`) whose public repos are
            trusted for routine clone/push/branch/PR in Claude auto-mode.
          '';
        };

        homelab = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Apply `homelab.environmentRules` to Claude auto-mode. Off by default
              so a fresh consumer gets a neutral classifier; set true in your own
              config alongside the rules describing your infrastructure.
            '';
          };

          environmentRules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Prose trusted-infrastructure rules appended to Claude auto-mode's
              `environment` when `homelab.enable` is true. Empty by default —
              describe your own infrastructure footprint here.
            '';
          };

          allowRules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Prose auto-permit rules appended to Claude auto-mode's `allow`
              when `homelab.enable` is true. Use for infrastructure actions the
              default soft-block list would otherwise stop but that your own
              tooling already gates (e.g. an IaC apply, or a secrets engine
              that enforces its own access separation). Empty by default so a
              fresh consumer keeps the neutral classifier.
            '';
          };
        };

        telemetry = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Emit Claude Code OpenTelemetry to `otlpEndpoint`. Off by default;
              requires a reachable OTLP collector. Enabling this without also
              setting `otlpEndpoint` emits nothing — see that option.
            '';
          };

          otlpEndpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "https://otel.example.internal";
            description = ''
              OTLP/HTTP base URL for Claude Code metrics and logs. The OTLP spec
              has the exporter append the signal path itself (`/v1/metrics`,
              `/v1/logs`), so this is the BASE url with no `/v1/...` suffix —
              unlike `tracesEndpoint`, which is signal-specific and must carry
              the full path.

              Null by default, and null means no OTLP export even when
              `enable` is true. There is deliberately no fallback default: a
              collector address is site-specific, and a wrong-but-plausible one
              exports into a black hole that looks identical to working
              telemetry. Kept out of the committed default for the same reason
              as `tracesEndpoint` — no private hostname in a public config.
            '';
          };

          tracesEndpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "https://otel.example.internal/v1/traces";
            description = ''
              Optional OTLP/HTTP endpoint for Claude Code *trace spans* only. When
              set (alongside telemetry.enable), the enhanced-telemetry tracing beta
              is turned on and trace spans are exported here over http/protobuf,
              while metrics and logs continue to otlpEndpoint. Unlike
              otlpEndpoint this is a signal-specific endpoint, so it must carry
              the full `/v1/traces` path — the exporter appends nothing. Leave
              null to emit no spans at all: plain `enable` yields counters and
              log events only, never the interaction/llm_request/tool/subagent
              span tree. Kept out of the committed default so no private
              hostname is baked into a public config — set it in your own user
              config.
            '';
          };
        };

        extraTrustedPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Extra directories Claude Code may access without per-prompt approval,
            appended to the built-in set. Use for personal tool caches.
          '';
        };

        trustedProjectDirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Directories under which Claude Code auto-approves a project's
            CLAUDE.md external imports without prompting. Clean by default;
            set to your own workspace roots (e.g. [ "~/git/public/" ]).
          '';
        };

        paths.git = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/git";
          description = ''
            Root of the local git checkout tree (defaults to `~/git`). The
            harnesses that trust or sandbox the workspace (Claude, Antigravity,
            Maestro) derive their paths from this, so a consumer relocates the
            workspace once instead of patching each hardcoded literal.
          '';
        };

        paths.public = lib.mkOption {
          type = lib.types.str;
          default = "${config.userConfig.paths.git}/public";
          description = ''
            Public workspace root (defaults to `~/git/public`), the directory
            under the git tree that holds public repositories. Shared by the
            permission engine's `directories.public` and the Antigravity
            sandbox allowlist, so the `public` literal lives in one place.
          '';
        };
      };
    };
    default = { };
    description = "Maintainer profile — the single consumer-overridable value surface for nix-ai.";
  };

  config._module.args.userConfig = lib.mkDefault config.userConfig;
}
