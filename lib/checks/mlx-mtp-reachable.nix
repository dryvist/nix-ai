# Reachability regression for programs.mlx.modelMtpProfiles.
#
# WHY ./mlx-catalog-vlm.nix does not cover this. Its mlx-mtp-native-contract
# check hand-builds a cfg attrset and calls model-server-cmd.nix directly, so
# the module system — and modules/mlx/assertions.nix with it — never runs. It
# answers "does a profile compile to the right argv?" and cannot answer "can a
# config ask for one?".
#
# Those came apart. From the day modelMtpProfiles landed until 2026-08-30 the
# answers were yes and no: the backend-policy assertion required
# `enabledBackends == [ "mlx-lm" ]` (exact equality) while the MTP assertion
# required `elem "mlx-vlm-native" cfg.enabledBackends`. No list satisfies both,
# so every enabled profile was rejected and the option was dead code — under a
# green check faithfully verifying a command line nothing could request.
#
# So this reads config.assertions off a REAL evaluation with a profile enabled.
# What each assert pins, in order:
#
#   1. every assertion holds — the thing a hand-built cfg cannot say
#   2. the backend-policy assertion, by message
#   3. the MTP profile assertion, by message
#   4. worker batch width is non-unit
#   5. the proxy gate equals it
#   6. a drafter is set
#   7. the drafter is not the target id reused
#
# 4 and 5 are separate on purpose. maxNumSeqs and modelConcurrencyLimits are
# both ints.between 1 4 and the assertion asks only that they be EQUAL, so a
# matched pair at 2 keeps that legible as a coupling; at 1 it is
# indistinguishable from "MTP must be serialized", which it is not.
#
# Assertions are located by `message`, not list index, as
# ./mlx-cluster-sharding.nix does it: an unrelated assertion landing beside
# these must not shift which one is read. The fixture lives here rather than in
# lib/checks.nix because that file sits ~100 bytes under the 12KB per-file
# error gate, and the repo splits rather than exempts.
{
  pkgs,
  mkHmConfig,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  target = "mlx-community/Qwen3.8-27B-4bit";

  hmConfigMtp = mkHmConfig [
    {
      programs.mlx = {
        # Stubbed as ./mlx-catalog-roles.nix stubs it: reading config.assertions
        # forces a judge message interpolating this option, which is types.str
        # with no default — otherwise eval throws instead of reporting.
        judge.model = "mlx-community/test-judge-model";
        defaultModelKey = "qwen38-27b";
        catalog.qwen38-27b.class = "resident";
        enabledBackends = [
          "mlx-lm"
          "mlx-vlm-native"
        ];
        modelBackends.${target} = "mlx-vlm-native";
        modelConcurrencyLimits.${target} = 2;
        modelMtpProfiles.${target} = {
          enable = true;
          # Native MTP tensors from Qwen/Qwen3.8-27B in the standalone MLX
          # drafter format mlx-vlm expects, quantized independently of the
          # target: this 6-bit drafter serves the 4-bit weights above.
          drafterModel = "lukaskremla/Qwen3.8-27B-MTP-6bit-MLX";
          maxNumSeqs = 2;
          draftBlockSize = 3;
        };
      };
    }
  ];

  cfg = hmConfigMtp.config.programs.mlx;
  profile = cfg.modelMtpProfiles.${target};

  failures = builtins.filter (a: !a.assertion) hmConfigMtp.config.assertions;
  failureMessages = builtins.concatStringsSep "\n  " (map (a: a.message) failures);

  assertionMatching =
    pattern:
    let
      matches = builtins.filter (
        a: builtins.match pattern a.message != null
      ) hmConfigMtp.config.assertions;
    in
    if builtins.length matches == 1 then
      (builtins.head matches).assertion
    else
      throw "mlx-mtp-reachable: expected exactly one assertion matching ${pattern}, found ${toString (builtins.length matches)}";
in
{
  mlx-mtp-reachable =
    assert
      failures == [ ]
      || throw "mlx mtp: a config with an enabled modelMtpProfiles entry must satisfy every assertion, but ${toString (builtins.length failures)} failed:\n  ${failureMessages}";
    assert
      assertionMatching ".*enabledBackends must not list vllm-mlx.*"
      || throw "mlx mtp: the backend-policy assertion must admit a config enabling mlx-vlm-native for one model; back at enabledBackends == [ \"mlx-lm\" ] it has re-killed every MTP profile";
    assert
      assertionMatching ".*requires the native mlx-vlm backend, a drafter.*"
      || throw "mlx mtp: the MTP profile assertion must hold for a correctly-formed profile (native backend, drafter set, matched concurrency, non-cluster)";
    assert
      profile.maxNumSeqs == 2
      || throw "mlx mtp: the fixture must keep a non-unit worker batch width, or the coupling reads as a requirement to serialize";
    assert
      cfg.modelConcurrencyLimits.${target} == 2
      || throw "mlx mtp: the proxy gate must equal the profile's maxNumSeqs; 2 is what proves the assertion couples them rather than capping at 1";
    assert
      profile.drafterModel != null
      || throw "mlx mtp: an enabled profile requires a drafter, and a null one must not evaluate";
    assert
      profile.drafterModel != target
      || throw "mlx mtp: the drafter must be a distinct artifact from its target, not the target id reused";
    helpers.mkMarker "check-mlx-mtp-reachable" "mlx mtp: an enabled modelMtpProfiles entry evaluates clean at a matched concurrency of 2";
}
