{
  pkgs,
  hmConfig,
  mkHmConfig,
}:
let
  overridden = mkHmConfig [
    {
      programs.codex = {
        approvalPolicy = "never";
        approvalsReviewer = "user";
      };
    }
  ];
in
{
  codex-approvals =
    assert overridden.config.programs.codex.approvalPolicy == "never";
    assert overridden.config.programs.codex.approvalsReviewer == "user";
    pkgs.runCommand "check-codex-approvals"
      {
        defaultActivation = hmConfig.config.home.activation.codexConfigMerge.data;
        overrideActivation = overridden.config.home.activation.codexConfigMerge.data;
        passAsFile = [
          "defaultActivation"
          "overrideActivation"
        ];
      }
      ''
        mkdir "$out"
        cp "$(grep -m1 -oE '/nix/store/[^"[:space:]]*codex-config\.toml' "$defaultActivationPath")" "$out/default.toml"
        cp "$(grep -m1 -oE '/nix/store/[^"[:space:]]*codex-config\.toml' "$overrideActivationPath")" "$out/override.toml"
        grep -Fxq 'sandbox_mode = "workspace-write"' "$out/default.toml"
        grep -Fxq 'sandbox_mode = "workspace-write"' "$out/override.toml"
        grep -Fxq 'approval_policy = "on-request"' "$out/default.toml"
        grep -Fxq 'approvals_reviewer = "auto_review"' "$out/default.toml"
        grep -Fxq 'approval_policy = "never"' "$out/override.toml"
        grep -Fxq 'approvals_reviewer = "user"' "$out/override.toml"
      '';
}
