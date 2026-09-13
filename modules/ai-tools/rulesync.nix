# Agent-config synchronizer — translates scoped rules (`globs:` source to
# `paths:` / `globs:` / `applyTo:` per target) and renders per-CLI hooks and
# permissions. Installed only; each consumer wires its own invocation.
#
# Its Codex hooks and permissions targets are project-scoped only
# (`getSettablePaths` ignores `global`), so user-level Codex files are written
# by Nix directly, never through this wrapper.
#
# Source: https://github.com/dyoshikawa/rulesync
# NPM: rulesync (pinned in lib/versions.nix). The name is contested on npm;
# the pin is verified against the dyoshikawa repository.
{ pkgs, versions }:
pkgs.writeShellScriptBin "rulesync" ''
  exec ${pkgs.bun}/bin/bunx --bun rulesync@${versions.rulesync} "$@"
''
