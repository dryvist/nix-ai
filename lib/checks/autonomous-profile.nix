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

        # Gemini: yolo under general, own sandbox disabled, policy referenced
        jq -e '.general.defaultApprovalMode == "yolo"' "$geminiSettingsPath"
        jq -e '.tools.sandbox == false' "$geminiSettingsPath"
        jq -e '.policyPaths | length == 1' "$geminiSettingsPath"

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
