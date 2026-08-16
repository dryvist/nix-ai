# The soak probe's busy-deferral behaviour and its call site.
#
# Split out of ./mlx-cluster-peer-armed.nix for the per-file 12KB gate (the
# same split-rather-than-exempt pattern .file-size.yml calls for). Different
# concern from the peer-armed handshake next door: this one is about not
# firing a probe at a pipeline that is already working.
{
  pkgs,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  readScript = f: builtins.readFile (src + "/modules/mlx/scripts/${f}");
  inherit (pkgs.lib) hasInfix;
in
{
  # because a wedged rank holds connections open the same way.
  mlx-cluster-soak-busy-defer = pkgs.runCommand "check-mlx-cluster-soak-busy-defer" {
    nativeBuildInputs = [ pkgs.coreutils ];
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
  } "bash ${src}/tests/test-soak-busy-defer.sh && touch $out";

  mlx-cluster-soak-busy-defer-calls =
    let
      watcherSrc = readScript "cluster-link-watcher.sh";
    in
    assert
      hasInfix "endpoint_busy" watcherSrc
      || throw "cluster: the soak re-check must consult endpoint_busy before probing. mlx-lm serializes generation and blocks HTTP, so a probe fired at a busy pipeline queues behind real work and expires through no fault of the mesh — on 2026-08-08 that killed a healthy rank mid-answer and the teardown leaked the wired shard on both hosts";
    assert
      hasInfix "CLUSTER_SOAK_BUSY_SKIP_MAX" watcherSrc
      || throw "cluster: the soak's deferral must be BOUNDED. A wedged rank holds its connections open exactly as a busy one does, so deferring on in-flight work alone would let a wedge that never closes its socket escape probing forever";
    helpers.mkMarker "check-mlx-cluster-soak-busy-defer-calls" "MLX soak re-check: defers to in-flight work and bounds the deferral";
}
