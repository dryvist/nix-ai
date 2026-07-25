# Builder for the cluster lifecycle commands (cluster-join / cluster-detach):
# supervised, verifiable front-ends over the watcher's already-designed
# teardown/bring-up. The whole CLUSTER_* env contract is baked at eval (mirrors
# the watcher agent) so the commands need no shell environment and behave
# identically on both nodes. System binaries (launchctl, ifconfig, ping, sysctl,
# sudo, pgrep) are called by absolute path — only curl/jq/coreutils ride the
# sanitized PATH.
#
# Split out of cluster-mode.nix for the per-file size cap, the same reason
# ./cluster-cli-env.nix was split out. The repo's .file-size.yml states the
# policy directly: files drifting toward the threshold are split rather than
# added to an extended-limit list.
{ lib, pkgs }:
name: scriptFile: env:
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = with pkgs; [
    curl
    jq
    coreutils
    git # generation-parity preflight (ls-remote)
  ];
  text = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") env
    ++ [ (builtins.readFile scriptFile) ]
  );
}
