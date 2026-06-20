# cecli — Nix Python derivation
#
# cecli (cecli-dev on PyPI) is the maintained fork of Aider. Built from
# the PyPI sdist via buildPythonApplication. Mirrors the shape of
# modules/fabric/package.nix.
#
# Two inline let-bound mini-derivations remain for transitive deps that
# nixpkgs-25.11 either ships at an incompatible version or doesn't ship
# at all:
#
#   - mcp 1.24.0 (sdist override) — nixpkgs has 1.15; cecli imports
#     streamable_http_client added in 1.24, so this is a hard
#     requirement, not a soft pin.
#   - py-cymbal (wheel) — Cymbal code-indexing native bindings; not in
#     nixpkgs at all. Wheel selection is platform-conditional (darwin
#     macOS arm64 vs linux manylinux2014 x86_64).
#
# Earlier revisions of this file inlined five additional derivations
# (`diff-match-patch`, `tree-sitter-c-sharp`, `tree-sitter-embedded-template`,
# `tree-sitter-yaml`, `tree-sitter-language-pack`). nixpkgs-25.11 now
# ships all five at compatible versions, so those went away.
#
# Five soft version pins are relaxed via postPatch against
# requirements/requirements.in — see the comment on postPatch below.
#
# uv2nix was evaluated as an alternative (PR #719 commit 590c1ba) and
# rejected: it would shift cecli's ~120-package closure from nixpkgs's
# curated supply chain (which OSV scanner trusts via its own audit
# process) to raw PyPI metadata, exposing the closure to fresh CVEs as
# upstream packages publish vulnerable versions. nixpkgs's slower
# bumps act as a security buffer for fast-moving Python deps.
#
# Usage: pkgs.callPackage ./package.nix { }

{
  lib,
  stdenv,
  python3Packages,
  fetchPypi,
  fetchurl,
}:

let
  # renovate: datasource=pypi depName=py-cymbal
  pyCymbalVersion = "0.1.24";
  py-cymbal = python3Packages.buildPythonPackage {
    pname = "py-cymbal";
    version = pyCymbalVersion;
    format = "wheel";
    src =
      if stdenv.isDarwin then
        fetchurl {
          url = "https://files.pythonhosted.org/packages/d9/02/58e39f04acbd2bd344f2f6dbdd70d191346817e0cade3c8c0311d3eeca95/py_cymbal-0.1.24-py3-none-macosx_11_0_arm64.whl";
          hash = "sha256-2A7libnzODdew8aOvZbOe3a2ZWlFlvhRj/kmXxeF01Q=";
        }
      else
        fetchurl {
          url = "https://files.pythonhosted.org/packages/70/52/646d527a501468562110aa10ca8805b01f11cada5b9de87fad428c0b8ab4/py_cymbal-0.1.24-py3-none-manylinux_2_17_x86_64.whl";
          hash = "sha256-QXLcVLGk0Qcrx+8fdiq9HWOcLQUmYd+QeRKjiJCrcvE=";
        };
    doCheck = false;
    pythonImportsCheck = [ ];
  };

  # mcp ≥ 1.24.0 added the streamable_http_client symbol that cecli
  # imports unconditionally. nixpkgs-25.11 ships mcp 1.15, so we
  # override locally for cecli only — other consumers keep the
  # nixpkgs version. This is one of the few pins we cannot relax via
  # postPatch because cecli imports a symbol that didn't exist yet.
  # renovate: datasource=pypi depName=mcp
  mcpVersion = "1.27.1";
  mcp = python3Packages.buildPythonPackage {
    pname = "mcp";
    version = mcpVersion;
    pyproject = true;
    src = fetchPypi {
      pname = "mcp";
      version = mcpVersion;
      hash = "sha256-D0fhgg+Pj5QUZrOXSesdGDmgTK3corxg6dRuipmRSSQ=";
    };
    build-system = with python3Packages; [
      hatchling
      uv-dynamic-versioning
    ];
    dependencies = with python3Packages; [
      anyio
      httpx-sse
      httpx
      jsonschema
      pydantic-settings
      pydantic
      pyjwt
      python-multipart
      sse-starlette
      starlette
      typing-extensions
      typing-inspection
      uvicorn
    ];
    doCheck = false;
    pythonImportsCheck = [ "mcp" ];
  };

  # renovate: datasource=pypi depName=cecli-dev
  version = "0.99.12";
in
python3Packages.buildPythonApplication {
  pname = "cecli";
  inherit version;
  pyproject = true;

  # PyPI normalizes the dist filename underscore (cecli_dev) but the
  # canonical package name uses a hyphen. fetchPypi takes the file-side
  # name; pname above is what shows up in `pip list`.
  src = fetchPypi {
    pname = "cecli_dev";
    inherit version;
    hash = "sha256-d1PZ2qco87+yQJPfzTxEygH1TLjXN+bwgrwaqTu8tls=";
  };

  # nixpkgs-25.11 ships older versions of several deps than cecli's
  # requirements/requirements.in lower bounds (gap is ~6 months — cecli
  # 0.99.10 came out 2026-05-04, nixpkgs 25.11 froze in 2025-11).
  # Functionally the older versions work; the lower bounds reflect
  # cecli upstream's "latest known good" tracking, not hard breakage.
  # Relax the bounds rather than carry five per-package overlay
  # overrides. Bumping nixpkgs eventually closes this gap.
  #
  # cecli's pyproject.toml uses dynamic deps sourced from
  # requirements/requirements.in (NOT inline pin strings), so the
  # substitutions target that file.
  postPatch = ''
    substituteInPlace requirements/requirements.in \
      --replace-quiet 'pypandoc>=1.15' 'pypandoc' \
      --replace-quiet 'litellm>=1.80.11,!=1.82.7,!=1.82.8' 'litellm' \
      --replace-quiet 'watchfiles>=1.1.0' 'watchfiles' \
      --replace-quiet 'tomlkit>=0.14.0' 'tomlkit' \
      --replace-quiet 'xxhash>=3.6.0' 'xxhash'
  '';

  build-system = with python3Packages; [
    setuptools
    setuptools-scm
    wheel
  ];

  dependencies =
    (with python3Packages; [
      pydub
      configargparse
      gitpython
      jsonschema
      rich
      prompt-toolkit
      backoff
      pathspec
      diskcache
      packaging
      sounddevice
      soundfile
      beautifulsoup4
      pyyaml
      pypandoc
      litellm
      flake8
      importlib-resources
      pyperclip
      pexpect
      json5
      psutil
      watchfiles
      socksio
      pillow
      shtab
      oslex
      textual
      tomlkit
      truststore
      xxhash
      rustworkx
      scipy
      importlib-metadata
      tree-sitter
      # nixpkgs-25.11 added these after the initial revision of this
      # file inlined them; using nixpkgs versions now.
      diff-match-patch
      tree-sitter-c-sharp
      tree-sitter-embedded-template
      tree-sitter-yaml
      tree-sitter-language-pack
    ])
    ++ [
      mcp
      py-cymbal
    ];

  # Tests need network (litellm provider calls) and audio devices
  # (pydub/sounddevice). Skip in Nix sandbox. The pythonImportsCheck
  # of the entry point at $out/bin/cecli runs separately as a smoke
  # test of the install layout.
  doCheck = false;
  pythonImportsCheck = [ "cecli" ];

  # Expose mcp as passthru so nix-update can manage its hash via --flake mcp
  passthru.mcp = mcp;

  meta = with lib; {
    description = "AI pair-programming CLI (maintained fork of Aider)";
    homepage = "https://github.com/cecli-dev/cecli";
    license = licenses.asl20;
    mainProgram = "cecli";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
  };
}
