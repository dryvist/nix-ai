# Autonomous-profile render checks
#
# Asserts the container-image configs produced by
# modules/common/render-autonomous.nix carry the expected postures:
# Claude bypassPermissions + residual deny, Codex never/danger-full-access,
# Gemini yolo with its own sandbox disabled. Guards against a refactor
# silently weakening (or accidentally host-deploying) the autonomous profile.
{ pkgs }:

let
  render = import ../../modules/common/render-autonomous.nix { inherit (pkgs) lib; };
in
{
  autonomous-profile-render =
    pkgs.runCommand "autonomous-profile-render"
      {
        nativeBuildInputs = [ pkgs.jq ];
        inherit (render) codexRules;
        claudeSettings = render.claudeSettingsJson;
        codexConfig = render.codexConfigToml;
        geminiSettings = render.geminiSettingsJson;
        passAsFile = [
          "claudeSettings"
          "codexConfig"
          "codexRules"
          "geminiSettings"
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

        # Gemini: yolo recorded, own sandbox disabled (container replaces it)
        jq -e '.defaultApprovalMode == "yolo"' "$geminiSettingsPath"
        jq -e '.tools.sandbox == false' "$geminiSettingsPath"

        touch "$out"
      '';
}
