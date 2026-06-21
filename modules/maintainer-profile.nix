# Maintainer profile — the single place for every consumer-overridable value.
#
# nix-ai is a reusable module: this file is the one knob surface a consumer
# touches to make the stack their own. Modules read `userConfig` via
# `_module.args` (bound at the bottom), so nothing else needs to import this.
#
# Posture (hybrid):
#   - Identity fields (`user.*`) default to the maintainer's values so the live
#     setup keeps working; a consumer overrides `user.fullName`/`trustedOrgs`.
#   - One-person infrastructure (`homelab.*`, `telemetry.*`, `extraTrustedPaths`,
#     `trustedProjectDirs`) defaults to clean/off, so `homeManagerModules.default`
#     evaluates to a neutral config with zero consumer input. The maintainer
#     re-enables these in their own consumer config (e.g. nix-darwin):
#       userConfig = { homelab.enable = true; telemetry.enable = true; };
#
# Declaring `userConfig` as a typed option gives consumers normal merge
# semantics (`userConfig.user.fullName = "Alice";`); binding `_module.args`
# to it avoids a self-reference cycle and stays `mkDefault` so the regression
# harness may inject `_module.args.userConfig` directly at higher priority.
{ lib, config, ... }:
let
  # OTEL endpoint comes from the cross-repo registry so the port stays in one
  # place (vars/ai-stack.nix nodeports.otel_grpc).
  aiVars = import ../vars/ai-stack.nix;
in
{
  options.userConfig = lib.mkOption {
    type = lib.types.submodule (
      { config, ... }:
      {
        options = {
          user = {
            fullName = lib.mkOption {
              type = lib.types.str;
              default = "JacobPEvans";
              description = "Full name / GitHub handle used to derive the trusted org and docs host.";
            };

            trustedOrgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "dryvist" ];
              description = ''
                Additional GitHub orgs (besides `fullName`) whose public repos are
                trusted for routine clone/push/branch/PR in Claude auto-mode.
              '';
            };

            docsHost = lib.mkOption {
              type = lib.types.str;
              default = "docs.${lib.toLower config.user.fullName}.com";
              description = "Public docs host referenced by the homelab auto-mode context.";
            };
          };

          homelab = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Apply the maintainer's homelab/day-job context to Claude auto-mode
                (`environmentRules`). Off by default so a fresh consumer gets a
                neutral classifier; the maintainer sets this true in their config.
              '';
            };

            environmentRules = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "Single-developer personal homelab plus day-job (Splunk/Cribl architect). Public docs map: https://${config.user.docsHost} (source github.com/${config.user.fullName}/docs) covers Infrastructure, Nix ecosystem, AI development, Observability, Security, and Tools surfaces."
                "Workspace layout: each repo is a clone on its default branch. Create an isolated worktree for feature work via the AI tool's native mechanism (Claude's EnterWorktree, which lands worktrees under .claude/worktrees/). Never run `git worktree add` into a path inside the repo's working tree — that pollutes the main checkout; place any manual worktree as a sibling of the clone, never a child."
                "Cloud: AWS via aws-vault profiles (terraform-aws, terraform-aws-bedrock); Proxmox cluster on the home LAN (terraform-proxmox plus ansible-proxmox-*). No multi-tenant production."
                "Secrets stores: Doppler (ai-ci-automation/prd project carries AI/MCP keys); macOS Keychain (ai-secrets keychain holds ANTHROPIC_API_KEY etc.; elevate-access keychain holds elevated GH tokens via the RESTRICTED/PRIVATE/ADMIN tier system); Mozilla SOPS handles at-rest encryption; Bitwarden vault plus Bitwarden Secrets Manager. No long-lived AWS keys — OIDC handles CI."
                "AI runtimes: local MLX server on this Mac (mlx-server devenv shell); Claude / Codex / Gemini / Copilot CLIs all routed through local dev shells; HuggingFace CLI handles model management."
                "Observability stack: OpenTelemetry instrumentation → Cribl Stream → Splunk Enterprise (homelab). splunk-dev devenv shell on local Splunk work."
                "Self-hosted runners: GitHub Actions self-hosted RunsOn runners labeled per the ${config.user.fullName}/.github v3 catalog. Jobs targeting RunsOn labels are routine."
                "Container deployment: LXC on Proxmox is the default in production homelab workloads. Docker only on vendor-locked images that require it (high-throughput network traffic must never flow through Docker's virtualized networking)."
                "Nix-first: nix-darwin (macOS), nix-home (cross-platform user env), nix-ai (AI tooling), nix-devenv (reusable dev shells plus flakeModules.dev-hygiene), nix-claude-code (Claude Code declarative module). Flakes-only — never use nix-env."
                "Pre-commit, linting, format: pre-commit hooks come from nix-devenv.flakeModules.dev-hygiene in Nix repos. zizmor policy from dryvist/.github (trusted publishers: actions/*, DeterminateSystems/*, googleapis/* may use ref-pins; everything else requires hash-pins)."
              ];
              description = ''
                Prose trusted-infrastructure rules appended to Claude auto-mode's
                `environment` when `homelab.enable` is true. Override wholesale to
                describe your own infrastructure footprint.
              '';
            };
          };

          telemetry = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Emit Claude Code OpenTelemetry to `otlpEndpoint`. Off by default;
                requires a reachable OTLP collector.
              '';
            };

            otlpEndpoint = lib.mkOption {
              type = lib.types.str;
              default = "http://localhost:${toString aiVars.nodeports.otel_grpc}";
              description = "OTLP gRPC endpoint for Claude Code telemetry when enabled.";
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
        };
      }
    );
    default = { };
    description = "Maintainer profile — the single consumer-overridable value surface for nix-ai.";
  };

  config._module.args.userConfig = lib.mkDefault config.userConfig;
}
