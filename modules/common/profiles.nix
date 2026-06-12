# Autonomy Profiles
#
# Tool-agnostic deployment profiles for the AI CLIs (Claude Code, Codex,
# Gemini). A profile answers one question: where does safety come from?
#
# - interactive: safety = the permission lists (allow/ask/deny) evaluated on
#   a trusted host with a human present. This is the existing Mac behavior;
#   the vendored nix-claude-code permission data remains its source of truth.
# - autonomous: safety = the container boundary. Tool permissions are
#   maximally lenient (bypass/never/yolo) because the agent runs inside an
#   ephemeral container with scoped credentials and default-deny egress.
#   Only a small residual deny list survives: operations the agent's
#   *credentials* could perform even though the filesystem/network boundary
#   holds (repo deletion, secret mutation, force-pushes, registry publish).
# - ci: autonomous plus non-interactive output conventions for GitHub
#   Actions runners.
#
# INVARIANT: the autonomous/ci configs are only ever baked into container
# images (see dryvist/nix-agent-sandbox). No home-manager code path may
# render them onto a host filesystem. Renderers live in
# render-autonomous.nix and are exposed via the flake's lib for image
# builds, not via the home-manager module.
{ lib }:

let
  # Commands denied even in bypass mode. These cross the container boundary
  # via credentials, not the filesystem, so the boundary alone cannot stop
  # them. Claude Code enforces permissions.deny even under
  # bypassPermissions; Codex carries the same list in its execpolicy rules
  # file. The real mitigation for all tools is credential scoping (1h
  # repo-scoped tokens) — this list is belt-and-suspenders.
  residualDeny = [
    "gh repo delete"
    "gh repo archive"
    "gh repo edit"
    "gh secret"
    "gh variable"
    "gh release delete"
    "gh auth"
    "gh api -X DELETE"
    "gh api --method DELETE"
    "git push --force"
    "git push -f"
    "git push --delete"
    "npm publish"
    "cargo publish"
  ];

  autonomous = {
    # Rendered per tool: Claude defaultMode = "bypassPermissions",
    # Codex approval_policy = "never" + sandbox_mode = "danger-full-access"
    # (the container IS the sandbox; bwrap cannot nest in unprivileged
    # containers), Gemini --approval-mode yolo with Gemini's own sandbox
    # disabled.
    approvalPosture = "bypass";

    # The ~640-entry interactive permission data does not apply: inside a
    # throwaway container, "is this command safe on my Mac?" is the wrong
    # question, and any surviving `ask` entry would stall a headless run.
    usesPermissionData = false;

    inherit residualDeny;

    # Image entrypoints must refuse to start the agent unless
    # AGENT_SANDBOX=1 is set (by the image itself) and uid != 0 (Claude
    # hard-rejects bypass mode as root).
    requiresContainerBoundary = true;
  };
in
{
  inherit residualDeny;

  interactive = {
    approvalPosture = "lists";
    usesPermissionData = true; # nix-claude-code data/permissions via permissions.nix
    requiresContainerBoundary = false;
  };

  inherit autonomous;

  ci = autonomous // {
    # Same posture; runners additionally launch with JSON output
    # (claude -p --output-format json etc.) — a launch-time concern,
    # not a settings-file concern.
    nonInteractiveOutput = true;
  };
}
