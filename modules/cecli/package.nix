# cecli — Nix Python derivation
#
# cecli (cecli-dev on PyPI) is the maintained fork of Aider. Built from
# the PyPI sdist via buildPythonApplication. Mirrors the shape of
# modules/mcp/pal-package.nix.
#
# Inline let-bound mini-derivations for transitive deps that
# nixpkgs-25.11 doesn't ship (or ships at incompatible versions):
#
#   Pure-Python sdist:
#     - diff-match-patch (Google's diff lib, flit-core build)
#
#   Wheel-only (native code; sdist would miss external_scanner symbol):
#     - py-cymbal (Cymbal code-indexing native bindings)
#     - tree-sitter-language-pack 0.13.0 (cecli pins <=0.13.0)
#     - tree-sitter-c-sharp / -embedded-template / -yaml (required by
#       tree-sitter-language-pack at module-init time)
#
#   Sdist override of older nixpkgs version:
#     - mcp 1.24.0 (nixpkgs has 1.15; cecli imports streamable_http_client
#       added in 1.24, so this is a hard requirement, not a soft pin)
#
# Wheel selection for wheel-only deps is platform-conditional: darwin
# uses macOS arm64 (universal2 for tslp), linux uses manylinux2014
# x86_64. The flake's supportedSystems covers aarch64-darwin +
# x86_64-linux; adding linux aarch64 means two more conditional URLs.
#
# Five soft version pins are relaxed via postPatch against
# requirements/requirements.in — see the comment on postPatch below.
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
  # renovate: datasource=pypi depName=diff-match-patch
  diffMatchPatchVersion = "20241021";
  diff-match-patch = python3Packages.buildPythonPackage rec {
    pname = "diff_match_patch";
    version = diffMatchPatchVersion;
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-vq5XqZ+kgIRTKTXuKWi4Zh24YYYuyCxvIfSs3W2DUHM=";
    };
    pyproject = true;
    build-system = [ python3Packages.flit-core ];
    doCheck = false;
    pythonImportsCheck = [ "diff_match_patch" ];
  };

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

  # The three tree-sitter language modules required by
  # tree-sitter-language-pack 0.13.0. None are in nixpkgs-25.11.
  # Use the upstream cp310-abi3 wheels (work for any CPython ≥3.10)
  # rather than building from sdist — sdist builds miss the
  # external_scanner.c symbol on darwin and produce broken .so files.
  mkTreeSitterLangWheel =
    {
      pname,
      version,
      darwinUrl,
      darwinHash,
      linuxUrl,
      linuxHash,
    }:
    python3Packages.buildPythonPackage {
      inherit pname version;
      format = "wheel";
      src =
        if stdenv.isDarwin then
          fetchurl {
            url = darwinUrl;
            hash = darwinHash;
          }
        else
          fetchurl {
            url = linuxUrl;
            hash = linuxHash;
          };
      propagatedBuildInputs = with python3Packages; [ tree-sitter ];
      doCheck = false;
      pythonImportsCheck = [ ];
    };

  tree-sitter-c-sharp = mkTreeSitterLangWheel {
    pname = "tree-sitter-c-sharp";
    version = "0.23.5";
    darwinUrl = "https://files.pythonhosted.org/packages/c8/13/593c8603f834eaf15082b81e079289fc9f062b4c0ab5b9489134084eec06/tree_sitter_c_sharp-0.23.5-cp310-abi3-macosx_11_0_arm64.whl";
    darwinHash = "sha256-p1mUoR9v7T9bjDatagDl3EMgW9kSxDrzoqVP32SWZOs=";
    linuxUrl = "https://files.pythonhosted.org/packages/41/5a/a8855cbb5bbab28adb29c2c7f0e7be5a9f1d21450c13b3c3e613190d9b8c/tree_sitter_c_sharp-0.23.5-cp310-abi3-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl";
    linuxHash = "sha256-qoingCBM0VPEwa4tWcZUzuFAIhL6DQaYI9bTQwFYdDg=";
  };

  tree-sitter-embedded-template = mkTreeSitterLangWheel {
    pname = "tree-sitter-embedded-template";
    version = "0.25.0";
    darwinUrl = "https://files.pythonhosted.org/packages/e8/ab/6d4e43b736b2a895d13baea3791dc8ce7245bedf4677df9e7deb22e23a2a/tree_sitter_embedded_template-0.25.0-cp310-abi3-macosx_11_0_arm64.whl";
    darwinHash = "sha256-/HqsvCmFpdfn/nM09E3/4kw4+wqClcQYigTPIaPWSnM=";
    linuxUrl = "https://files.pythonhosted.org/packages/9f/97/ea3d1ea4b320fe66e0468b9f6602966e544c9fe641882484f9105e50ee0c/tree_sitter_embedded_template-0.25.0-cp310-abi3-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl";
    linuxHash = "sha256-p8iMPdi5Szye/orgcf9rG5NqJ6xfbmUYRcO5Yx+kwcI=";
  };

  tree-sitter-yaml = mkTreeSitterLangWheel {
    pname = "tree-sitter-yaml";
    version = "0.7.2";
    darwinUrl = "https://files.pythonhosted.org/packages/18/0d/15a5add06b3932b5e4ce5f5e8e179197097decfe82a0ef000952c8b98216/tree_sitter_yaml-0.7.2-cp310-abi3-macosx_11_0_arm64.whl";
    darwinHash = "sha256-CAe3lm4j3ffd3EVFIW4otaWM2t7c7MqGuNjHQnGgeHA=";
    linuxUrl = "https://files.pythonhosted.org/packages/72/92/c4b896c90d08deb8308fadbad2210fdcc4c66c44ab4292eac4e80acb4b61/tree_sitter_yaml-0.7.2-cp310-abi3-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl";
    linuxHash = "sha256-8aXGDJi2xMA3quAjVp8CDQxIn62Nwm/f1VEDY8nCmkE=";
  };

  # tree-sitter-language-pack: cecli upstream pins <=0.13.0. The 0.13.0
  # wheels use the cp310-abi3 stable ABI tag — work for any CPython
  # ≥3.10. Universal2 darwin wheel covers both arm64 and x86_64.
  # Three tree-sitter-* packages above are propagated as runtime deps.
  treeSitterLanguagePackVersion = "0.13.0";
  tree-sitter-language-pack = python3Packages.buildPythonPackage {
    pname = "tree-sitter-language-pack";
    version = treeSitterLanguagePackVersion;
    format = "wheel";
    src =
      if stdenv.isDarwin then
        fetchurl {
          url = "https://files.pythonhosted.org/packages/e9/38/aec1f450ae5c4796de8345442f297fcf8912c7d2e00a66d3236ff0f825ed/tree_sitter_language_pack-0.13.0-cp310-abi3-macosx_10_15_universal2.whl";
          hash = "sha256-Dn6ugStAotyKEusvXFXhMOuJJwagvuBiFd12r/6wDQc=";
        }
      else
        fetchurl {
          url = "https://files.pythonhosted.org/packages/72/9d/644db031047ab1a70fc5cb6a79a4d4067080fac628375b2320752d2d7b58/tree_sitter_language_pack-0.13.0-cp310-abi3-manylinux2014_x86_64.whl";
          hash = "sha256-DU8mH844euBA2ufk0cGspj2EyIMgr8wJYcEjvsC+g3c=";
        };
    propagatedBuildInputs =
      with python3Packages;
      [
        tree-sitter
      ]
      ++ [
        tree-sitter-c-sharp
        tree-sitter-embedded-template
        tree-sitter-yaml
      ];
    doCheck = false;
    pythonImportsCheck = [ ];
  };

  # mcp ≥ 1.24.0 added the streamable_http_client symbol that cecli
  # imports unconditionally. nixpkgs-25.11 ships mcp 1.15, so we
  # override locally for cecli only — other consumers keep the
  # nixpkgs version. This is one of the few pins we cannot relax via
  # postPatch because cecli imports a symbol that didn't exist yet.
  # renovate: datasource=pypi depName=mcp
  mcpVersion = "1.24.0";
  mcp = python3Packages.buildPythonPackage {
    pname = "mcp";
    version = mcpVersion;
    pyproject = true;
    src = fetchPypi {
      pname = "mcp";
      version = mcpVersion;
      hash = "sha256-rqrRNGZM5W8nIdGr8wBmah6DSFY/TTuv82HDtlJEjvw=";
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
  version = "0.99.10";
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
    hash = "sha256-kDJ+DfCFz+CJxEjWWeISodAcFdUGSl6wElOZH8rYmVE=";
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
    ])
    ++ [
      diff-match-patch
      mcp
      py-cymbal
      tree-sitter-language-pack
    ];

  # Tests need network (litellm provider calls) and audio devices
  # (pydub/sounddevice). Skip in Nix sandbox. The pythonImportsCheck
  # of the entry point at $out/bin/cecli runs separately as a smoke
  # test of the install layout.
  doCheck = false;
  pythonImportsCheck = [ "cecli" ];

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
