# Sharding-mode regression test for modules/mlx/cluster-assertions.nix.
#
# The two sharding assertions are converses and neither substitutes the other.
# One rejects a pipeline-only architecture left on the tensor-parallel default,
# where mlx-lm splits nothing and every rank loads the whole model in silence.
# The other rejects shardingMode = "pipeline" on an architecture mlx-lm never
# pipelines, which aborts at rank start — loudly, but only after the wired
# ceiling is applied and a protection domain is spent, and nothing short of a
# reboot returns that domain.
#
# WHY THERE IS NO NEGATIVE FIXTURE. modelCatalogKey is an enum over the
# cluster-eligible catalog entries (options-cluster.nix filters on `cluster`),
# and exactly one entry is eligible today, so no config can name an
# unpipelineable architecture — the module system refuses the option value long
# before an assertion sees it. The converse assertion is the guard standing
# ready the day a second cluster model lands; what this check holds until then
# is that it EXISTS, is reachable, and does not contradict its sibling on the
# model this pair actually runs. Deleting either assertion fails this check.
#
# Both are located by `message` rather than by list index, the same way
# ./mlx-catalog-roles.nix reads its assertions: an unrelated assertion landing
# beside these must not make the check silently read a different one.
{
  pkgs,
  hmConfigCluster,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  assertionMatching =
    pattern:
    let
      matches = builtins.filter (
        a: builtins.match pattern a.message != null
      ) hmConfigCluster.config.assertions;
    in
    if builtins.length matches == 1 then
      (builtins.head matches).assertion
    else
      throw "mlx-cluster-sharding: expected exactly one clusterMode assertion matching ${pattern}, found ${toString (builtins.length matches)}";
in
{
  mlx-cluster-sharding =
    assert
      assertionMatching ".*implements pipelining and NOT tensor parallelism.*"
      || throw "cluster sharding: glm4_moe on shardingMode = \"pipeline\" is the supported pairing and must satisfy the pipeline-only assertion";
    assert
      assertionMatching ".*which mlx-lm does not pipeline.*"
      || throw "cluster sharding: glm4_moe is pipeline-capable, so naming shardingMode = \"pipeline\" on it must satisfy the converse assertion too — two assertions that disagree on the model this pair runs would make one of them unsatisfiable";
    helpers.mkMarker "check-mlx-cluster-sharding" "cluster sharding: the pipeline-only and pipeline-capable assertions are both present and agree on the deployed cluster model";
}
