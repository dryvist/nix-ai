{
  pkgs,
  hmConfig,
  mkHmConfig,
}:
let
  sandboxDefaults = import ../../modules/codex/sandbox-defaults.nix;
  overridden = mkHmConfig [
    {
      programs.codex = {
        approvalPolicy = "never";
        approvalsReviewer = "user";
        writableRoots = [ "/tmp/codex-workspace" ];
      };
    }
  ];
in
{
  codex-approvals =
    assert overridden.config.programs.codex.approvalPolicy == "never";
    assert overridden.config.programs.codex.approvalsReviewer == "user";
    assert overridden.config.programs.codex.writableRoots == [ "/tmp/codex-workspace" ];
    assert !hmConfig.config.programs.litellmLocal.enable;
    pkgs.runCommand "check-codex-approvals"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.jq
          pkgs.yj
        ];
        defaultActivation = hmConfig.config.home.activation.codexConfigMerge.data;
        overrideActivation = overridden.config.home.activation.codexConfigMerge.data;
        expectedRoots = builtins.toJSON (
          sandboxDefaults.writableRoots {
            inherit (pkgs) lib;
            inherit (hmConfig.config.home) homeDirectory;
            inherit (pkgs.stdenv.hostPlatform) isDarwin;
          }
        );
        projectRoot = "/Volumes/git/${hmConfig.config.home.username}";
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
        yj -tj < "$out/default.toml" | jq -e \
          --argjson roots "$expectedRoots" --arg root "$projectRoot" '
          .sandbox_workspace_write == {network_access: true, writable_roots: $roots}
          and .projects[($root + "/public")].trust_level == "trusted"
          and .projects[($root + "/private")].trust_level == "trusted"
        ' >/dev/null
        yj -tj < "$out/override.toml" | jq -e '
          .sandbox_workspace_write == {
            network_access: true, writable_roots: ["/tmp/codex-workspace"]
          }
        ' >/dev/null
      '';

  codex-config-merge =
    pkgs.runCommand "check-codex-config-merge"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.gnugrep
          pkgs.jq
          pkgs.yj
        ];
        activation = hmConfig.config.home.activation.codexConfigMerge.data;
        passAsFile = [ "activation" ];
      }
      ''
        mkdir "$out"
        toml=$(grep -m1 -oE '/nix/store/[^"[:space:]]*codex-config\.toml' "$activationPath")
        yj -tj < "$toml" > expected.json
        jq 'del(.sandbox_workspace_write) | .runtime_marker = "preserved"
          | .projects["/runtime/worktree"].trust_level = "trusted"' expected.json \
          | yj -jt > "$out/config.toml"
        bash ${../../modules/scripts/merge-toml-settings.sh} "$toml" "$out/config.toml"
        yj -tj < "$out/config.toml" | jq -e --slurpfile expected expected.json '
          .sandbox_workspace_write == $expected[0].sandbox_workspace_write
          and .runtime_marker == "preserved"
          and .projects["/runtime/worktree"].trust_level == "trusted"
        ' >/dev/null
        yj -tj < "$out/config.toml" | jq -S . > "$out/first.json"
        bash ${../../modules/scripts/merge-toml-settings.sh} "$toml" "$out/config.toml"
        yj -tj < "$out/config.toml" | jq -S . > "$out/repeated.json"
        cmp "$out/first.json" "$out/repeated.json"
        yj -tj < "$out/config.toml" | jq '
          .sandbox_workspace_write = {network_access: false, writable_roots: ["/stale"]}
        ' | yj -jt > "$out/stale.toml"
        bash ${../../modules/scripts/merge-toml-settings.sh} "$toml" "$out/stale.toml"
        yj -tj < "$out/stale.toml" | jq -S . > "$out/stale.json"
        cmp "$out/first.json" "$out/stale.json"
      '';
}
