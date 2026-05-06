# cecli — uv2nix-built Python application.
#
# Builds cecli-dev from PyPI via the uv.lock + pyproject.toml shim in
# this directory. uv.lock is hash-pinned and Renovate-managed.
#
# Why uv2nix and not nixpkgs' python3Packages: cecli's runtime closure
# spans ~120 packages, several of which nixpkgs ships at versions
# incompatible with cecli (e.g. mcp 1.15 vs cecli's required >=1.24)
# or doesn't ship at all (py-cymbal). Rather than carry inline overrides
# for each gap, uv2nix builds the whole closure from PyPI directly so
# nixpkgs version churn is decoupled from cecli's deps.
#
# Repo standard for any new PyPI-fetched Python tool — see
# docs/architecture/per-agent-flakes.md. Renovate manages the version
# pin in pyproject.toml; bumping it triggers
# `uv lock --upgrade-package cecli-dev` which regenerates uv.lock.

{
  lib,
  callPackage,
  python3,
  pyproject-nix,
  uv2nix,
  pyproject-build-systems,
}:

let
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  pythonSet = (callPackage pyproject-nix.build.packages { python = python3; }).overrideScope (
    lib.composeManyExtensions [
      pyproject-build-systems.overlays.wheel
      overlay
    ]
  );

  venv = pythonSet.mkVirtualEnv "cecli" workspace.deps.default;
in
venv.overrideAttrs (old: {
  meta = (old.meta or { }) // {
    description = "AI pair-programming CLI (maintained fork of Aider)";
    homepage = "https://github.com/cecli-dev/cecli";
    license = lib.licenses.asl20;
    mainProgram = "cecli";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
  };
})
