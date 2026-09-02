# Stable store-path links for agent trees.
#
# `mkStableLinks` takes an attrset of `home-relative path -> store path` and
# returns a home-manager activation entry that symlinks each one directly at its
# own store path, instead of routing it through home-manager's aggregate
# `home-manager-files` derivation.
#
# Why this exists: that aggregate's hash covers the whole home configuration, so
# it changes on every rebuild regardless of whether the linked content changed.
# Every AI CLI caches against these paths — Claude Code pins plugin
# installPaths, and Codex, Cursor, OpenCode, qwen and Antigravity read the
# shared skill tree — so a moved target invalidates those caches and breaks
# sessions that are already running, until the user reloads by hand. Linking to
# the per-item store path keeps the target byte-stable across unrelated
# rebuilds.
{ lib, pkgs }:
{
  # name  : activation entry name, for the generation diff
  # links : { "relative/path" = <store path>; }
  mkStableLinks =
    name: links:
    let
      manifest = pkgs.writeText "${name}-manifest" (
        lib.concatStringsSep "\n" (lib.mapAttrsToList (rel: target: "${rel}\t${target}") links) + "\n"
      );
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${./stable-links.sh} ${manifest} "$HOME"
    '';
}
