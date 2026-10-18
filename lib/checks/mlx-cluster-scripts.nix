# Build the peer-state responder and the two explicit lifecycle commands.
{
  pkgs,
  hmConfigCluster,
}:
let
  agents = hmConfigCluster.config.launchd.agents;
  agentExes = map (name: pkgs.lib.last agents.${name}.config.ProgramArguments) [
    "mlx-cluster-peer-state"
  ];
  cliExes = map pkgs.lib.getExe (
    builtins.filter (
      p:
      builtins.elem (p.name or "") [
        "cluster-join"
        "cluster-detach"
      ]
    ) hmConfigCluster.config.home.packages
  );
in
{
  mlx-cluster-scripts-build = pkgs.runCommand "check-mlx-cluster-scripts-build" { } ''
    for exe in ${pkgs.lib.concatStringsSep " " (agentExes ++ cliExes)}; do
      test -x "$exe" || {
        echo "cluster script not executable: $exe" >&2
        exit 1
      }
    done
    touch $out
  '';
}
