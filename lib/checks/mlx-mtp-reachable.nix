# Reachability regression for programs.mlx.modelMtpProfiles.
#
# WHAT THIS GUARDS, and why ./mlx-catalog-vlm.nix does not already guard it.
#
# That file's mlx-mtp-native-contract check synthesizes a cfg attrset by hand
# and calls model-server-cmd.nix directly. It never evaluates the module
# system, so modules/mlx/assertions.nix never runs against it. It therefore
# answers "does an MTP profile compile to the right argv?" and cannot answer
# "can any configuration actually ask for one?".
#
# Those came apart. From the day modelMtpProfiles landed until 2026-08-30 the
# answers were yes and no: the backend-policy assertion required
# `enabledBackends == [ "mlx-lm" ]` (exact equality) while the MTP assertion
# required `elem "mlx-vlm-native" cfg.enabledBackends`. No list satisfies both,
# so every enabled profile failed one assertion or the other and the entire
# option surface was unreachable — with a green check sitting on top of it,
# faithfully verifying a command line nothing could request.
#
# This check closes that gap by reading config.assertions off a REAL evaluation
# (lib/checks.nix `hmConfigMtp`) with a profile enabled. A contradiction
# reintroduced anywhere in that assertion list fails here.
#
# Assertions are located by `message` rather than by list index, the same way
# ./mlx-cluster-sharding.nix and ./mlx-catalog-roles.nix do it: an unrelated
# assertion landing beside these must not silently shift which one is read.
#
# Takes `mkHmConfig` and builds its own fixture, unlike its siblings which
# receive a prebuilt one: lib/checks.nix sits ~100 bytes under the 12KB
# per-file error gate, and the repo splits rather than exempts.
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
    # only that they be equal; the matched pair here is 2. Pinned because the
    # 1-1 case is indistinguishable from "MTP must be serialized", and reading
    # it that way is the mistake this line exists to prevent.
    assert
      profile.maxNumSeqs == 2 && cfg.modelConcurrencyLimits.${target} == 2
      || throw "mlx mtp: the fixture must keep a MATCHED non-unit concurrency pair, so the coupling cannot be misread as a requirement to serialize";

    # The drafter is a separate Hub artifact in mlx-vlm's standalone format and
    # is quantized independently of the target — a 6-bit drafter against 4-bit
    # weights. Pinned so a future edit cannot quietly assume they must match.
    assert
      profile.drafterModel != null && profile.drafterModel != target
      || throw "mlx mtp: an enabled profile needs a drafter distinct from its target";

    helpers.mkMarker "check-mlx-mtp-reachable" "mlx mtp: an enabled modelMtpProfiles entry evaluates clean at a matched concurrency of 2";
}
