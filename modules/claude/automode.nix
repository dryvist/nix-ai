# Claude Code auto-mode classifier configuration.
#
# Imported by programs.claude.autoMode in claude-config.nix and read by
# Claude's auto-mode classifier as prose rules. Each field is a list of
# natural-language strings; `$defaults` inherits Claude Code's built-in
# rules at that position. Reference:
# https://code.claude.com/docs/en/auto-mode-config.
#
#   environment - trusted-infrastructure context, so routine cross-repo,
#                 cross-org, cloud, and homelab actions are not flagged
#                 as exfiltration.
#   allow       - exceptions that auto-permit actions the default
#                 soft-block list would otherwise stop.
#   soft_deny   - destructive actions that need explicit user intent or
#                 an `allow` exception before proceeding.
#
# Source-of-truth context lives at https://docs.jacobpevans.com
# (source: github.com/JacobPEvans/docs). Update entries here when the
# trusted infrastructure footprint changes.
#
# Sources the GitHub username from userConfig.user.fullName so the
# value stays consistent with lib/user-config.nix. The secondary
# `dryvist` org is hardcoded — it's a separate GitHub organization,
# not part of the user's primary identity, so not modeled in userConfig.
{ userConfig, lib }:
let
  ghUser = userConfig.user.fullName;
  docsHost = "docs.${lib.toLower ghUser}.com";
in
{
  environment = [
    "$defaults"
    "Single-developer personal homelab plus day-job (Splunk/Cribl architect). Public docs map: https://${docsHost} (source github.com/${ghUser}/docs) covers Infrastructure, Nix ecosystem, AI development, Observability, Security, and Tools surfaces."
    "Source control: GitHub orgs github.com/${ghUser}/* and github.com/dryvist/*. All public repos under both are trusted to clone, push, branch, and PR-mutate against. Force-push to feature branches is routine; force-push to main is off-limits."
    "Workspace layout: ~/git/<repo>/main is the main-branch worktree. Feature work happens in ~/git/<repo>/<type>/<name>/ via git worktrees. Standard across every repo."
    "Cloud: AWS via aws-vault profiles (terraform-aws, terraform-aws-bedrock); Proxmox cluster on the home LAN (terraform-proxmox plus ansible-proxmox-*). No multi-tenant production."
    "Secrets stores: Doppler (ai-ci-automation/prd project carries AI/MCP keys); macOS Keychain (ai-secrets keychain holds ANTHROPIC_API_KEY etc.; elevate-access keychain holds elevated GH tokens via the RESTRICTED/PRIVATE/ADMIN tier system); Mozilla SOPS handles at-rest encryption; Bitwarden vault plus Bitwarden Secrets Manager. No long-lived AWS keys — OIDC handles CI."
    "AI runtimes: local MLX server on this Mac (mlx-server devenv shell); Claude / Codex / Gemini / Copilot CLIs all routed through local dev shells; PAL MCP proxy handles multi-model orchestration; HuggingFace CLI handles model management."
    "Observability stack: OpenTelemetry instrumentation → Cribl Stream → Splunk Enterprise (homelab). splunk-dev devenv shell on local Splunk work."
    "Self-hosted runners: GitHub Actions self-hosted RunsOn runners labeled per the ${ghUser}/.github v3 catalog. Jobs targeting RunsOn labels are routine."
    "Container deployment: LXC on Proxmox is the default in production homelab workloads. Docker only on vendor-locked images that require it (high-throughput network traffic must never flow through Docker's virtualized networking)."
    "Nix-first: nix-darwin (macOS), nix-home (cross-platform user env), nix-ai (AI tooling), nix-devenv (reusable dev shells plus flakeModules.dev-hygiene), nix-claude-code (Claude Code declarative module). Flakes-only — never use nix-env."
    "Pre-commit, linting, format: pre-commit hooks come from nix-devenv.flakeModules.dev-hygiene in Nix repos. zizmor policy from dryvist/.github (trusted publishers: actions/*, DeterminateSystems/*, googleapis/* may use ref-pins; everything else requires hash-pins)."
  ];

  allow = [
    "$defaults"
    "Running `rm` to delete files inside the current working repository is routine and safe — allow without confirmation, including recursive deletion of ordinary subdirectories such as build outputs, caches, vendored dependencies, test fixtures, and git worktrees."
  ];

  soft_deny = [
    "$defaults"
    "Require confirmation before a forced or recursive `rm` that could be catastrophic: deleting the entire working repository, removing any path outside the current repo, or wiping large or untracked directory trees. Deleting individual files or ordinary subdirectories inside the repo does not need confirmation."
  ];
}
