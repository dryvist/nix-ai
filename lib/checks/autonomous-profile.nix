# Autonomous-profile render checks
#
# Asserts the container-image configs produced by
# modules/common/render-autonomous.nix carry the expected postures —
# Claude bypassPermissions, Codex never/danger-full-access, Gemini yolo
# with its own sandbox disabled — and that ALL THREE tools inherit the
# same residualDeny list in their native formats. Guards against a
# refactor silently weakening (or accidentally host-deploying) the
# autonomous profile.
{ pkgs }:

let
  render = import ../../modules/common/render-autonomous.nix { inherit (pkgs) lib; };
in
{
  autonomous-profile-render =
    pkgs.runCommand "autonomous-profile-render"
      {
        nativeBuildInputs = [ pkgs.jq ];
        inherit (render) codexRules geminiPolicyToml;
        claudeSettings = render.claudeSettingsJson;
        codexConfig = render.codexConfigToml;
        geminiSettings = render.geminiSettingsJson;
        passAsFile = [
          "claudeSettings"
          "codexConfig"
          "codexRules"
          "geminiSettings"
          "geminiPolicyToml"
        ];
      }
      ''
        set -euo pipefail

        # Claude: valid JSON, bypass mode, empty allow/ask, residual deny present
        jq -e '.permissions.defaultMode == "bypassPermissions"' "$claudeSettingsPath"
        jq -e '.permissions.allow == [] and .permissions.ask == []' "$claudeSettingsPath"
        jq -e '.permissions.deny | index("Bash(gh repo delete *)")' "$claudeSettingsPath"
        jq -e '.permissions.deny | index("Bash(git push --force *)")' "$claudeSettingsPath"

        # Codex: container-is-the-sandbox posture + residual deny in rules
        grep -q 'approval_policy = "never"' "$codexConfigPath"
        grep -q 'sandbox_mode = "danger-full-access"' "$codexConfigPath"
        grep -q '"forbidden"' "$codexRulesPath"
        grep -Fq '["gh","repo","delete"]' "$codexRulesPath"

        # Gemini: own sandbox disabled, policy referenced, auth pinned so a
        # headless run does not stop at the interactive picker.
        jq -e '.tools.sandbox == false' "$geminiSettingsPath"
        jq -e '.policyPaths | length == 1' "$geminiSettingsPath"
        jq -e '.security.auth.selectedType == "oauth-personal"' "$geminiSettingsPath"

        # ASSERT ABSENT, not present: gemini-cli 0.53 hard-errors on
        # general.defaultApprovalMode = "yolo" (invalid enum) and refuses to
        # start, so rendering it would break the tool. The autonomous posture
        # rides the launch flag instead. This check previously REQUIRED the
        # key — it was enforcing a config that could not run.
        jq -e '.general.defaultApprovalMode == null' "$geminiSettingsPath"

        # Gemini Policy Engine TOML: deny rules from the same shared list
        grep -q 'commandPrefix = "gh repo delete"' "$geminiPolicyTomlPath"
        grep -q 'decision = "deny"' "$geminiPolicyTomlPath"
        grep -q 'priority = 200' "$geminiPolicyTomlPath"

        # Single-list inheritance: each tool's output carries the SAME
        # number of deny entries as the shared residualDeny list.
        n=${toString (builtins.length render.residualDeny)}
        jq -e ".permissions.deny | length == $n" "$claudeSettingsPath"
        [ "$(grep -c '"forbidden"' "$codexRulesPath")" -eq "$n" ]
        [ "$(grep -c 'decision = "deny"' "$geminiPolicyTomlPath")" -eq "$n" ]

        touch "$out"
      '';
}
