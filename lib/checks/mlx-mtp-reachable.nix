# Reachability regression for programs.mlx.modelMtpProfiles.
#
# WHY ./mlx-catalog-vlm.nix does not already cover this. Its
# mlx-mtp-native-contract check hand-builds a cfg attrset and calls
# model-server-cmd.nix directly, so the module system — and therefore
# modules/mlx/assertions.nix — never runs. It answers "does a profile compile
# to the right argv?" and cannot answer "can a config ask for one?".
#
# Those came apart. From the day modelMtpProfiles landed until 2026-08-30 the
# answers were yes and no: the backend-policy assertion required
# `enabledBackends == [ "mlx-lm" ]` (exact equality) while the MTP assertion
# required `elem "mlx-vlm-native" cfg.enabledBackends`. No list satisfies both,
# so every enabled profile was rejected and the option was dead code — under a
# green check faithfully verifying a command line nothing could request.
#
# So this reads config.assertions off a REAL evaluation with a profile enabled,
# and fails if a contradiction is reintroduced anywhere in that list.
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

  # concurrency 2, deliberately: maxNumSeqs and modelConcurrencyLimits are both
  # types.ints.between 1 4 and the assertion requires only that they be EQUAL.
  # A matched pair at 2 keeps that legible as a coupling; at 1 it is
  # indistinguishable from "MTP must be serialized", which it is not.
  hmConfigMtp = mkHmConfig [
    {
      programs.mlx = {
        # Stubbed as ./mlx-catalog-roles.nix stubs it: reading config.assertions
        # forces a judge message that interpolates this option, which is
        # types.str with no default — otherwise eval throws instead of reporting.
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
          # drafter format mlx-vlm expects. Quantized independently of the
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
    # THE POINT OF THE FILE. A config with an enabled MTP profile must evaluate
    # with every assertion satisfied. This is what a hand-built cfg cannot say.
    assert
      failures == [ ]
      || throw "mlx mtp: a configuration with an enabled modelMtpProfiles entry must satisfy every assertion, but ${toString (builtins.length failures)} failed:\n  ${failureMessages}";

    # Both halves of the contradiction, pinned individually so a regression
    # names which one came back — the aggregate above would only say "one of
    # them", and these two have been mutually unsatisfiable before.
    assert
      assertionMatching ".*enabledBackends must not list vllm-mlx.*"
      || throw "mlx mtp: the backend-policy assertion must admit a config that enables mlx-vlm-native for one model; if it is back to demanding enabledBackends == [ \"mlx-lm\" ] it has re-killed every MTP profile";
    assert
      assertionMatching ".*requires the native mlx-vlm backend, a drafter.*"
      || throw "mlx mtp: the MTP profile assertion must hold for a correctly-formed profile (native backend, drafter set, matched concurrency, non-cluster)";

    # Concurrency is a COUPLING, not a cap at 1. maxNumSeqs and
    # modelConcurrencyLimits are both ints.between 1 4 and the assertion asks
    # only that they be equal; the matched pair here is 2. Pinned as two
    # separate asserts because the 1-1 case is indistinguishable from "MTP must
    # be serialized", and a failure should name which half moved.
    assert
      profile.maxNumSeqs == 2
      || throw "mlx mtp: the fixture must keep a non-unit worker batch width, or the coupling reads as a requirement to serialize";
    assert
      cfg.modelConcurrencyLimits.${target} == 2
      || throw "mlx mtp: the proxy gate must equal the profile's maxNumSeqs; 2 is what proves the assertion couples them rather than capping at 1";

    # The drafter is a separate Hub artifact in mlx-vlm's standalone format,
    # quantized independently of the target — a 6-bit drafter against 4-bit
    # weights. Pinned so a future edit cannot quietly assume they must match.
    assert profile.drafterModel != null || throw "mlx mtp: an enabled profile needs a drafter";
    assert
      profile.drafterModel != target
      || throw "mlx mtp: the drafter must be a distinct artifact from its target, not the target id reused";

    helpers.mkMarker "check-mlx-mtp-reachable" "mlx mtp: an enabled modelMtpProfiles entry evaluates clean at a matched concurrency of 2";
}
