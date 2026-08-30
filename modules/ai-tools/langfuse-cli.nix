# Langfuse API CLI — traces, prompts, datasets, scores.
# NPM: langfuse-cli (pinned in lib/versions.nix); global install exposes `langfuse`.
{ pkgs, langfuseCliVersion }:
pkgs.writeShellScriptBin "langfuse" ''
  exec ${pkgs.bun}/bin/bunx --bun langfuse-cli@${langfuseCliVersion} "$@"
''
