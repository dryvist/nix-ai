# Cursor CLI Package
#
# Cursor's terminal coding agent (`agent` / `cursor-agent`) from the official
# lab download channel. Two-platform derivation (x86_64-linux, aarch64-darwin)
# matching the flake's supported systems. Version pin lives in lib/versions.nix.
#
# The lab channel uses a date+short-hash scheme (e.g., 2026.09.02-c22c1a3)
# with no datasource; bump manually per the procedure in modules/cursor/README.md.
#
# The tarball layout varies by release: some ship a flat `cursor-agent` binary
# at the root, others nest it under `dist-package/cursor-agent`. The install
# phase handles both and fails loudly if neither is found.
{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = (import ../../lib/versions.nix).cursorCli;

  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/${version}/linux/x64/agent-cli-package.tar.gz";
      hash = lib.fakeHash;
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/${version}/darwin/arm64/agent-cli-package.tar.gz";
      hash = lib.fakeHash;
    };
  };
in
stdenv.mkDerivation {
  pname = "cursor-cli";
  inherit version;

  src = sources.${hostPlatform.system};

  buildInputs = lib.optionals hostPlatform.isLinux [
    zlib
  ];

  nativeBuildInputs = lib.optionals hostPlatform.isLinux [
    autoPatchelfHook
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/cursor-agent

    # The tarball layout varies: some releases have a flat `cursor-agent`
    # at the root, others nest it under `dist-package/cursor-agent`.
    # Handle both; fail loudly if neither is found.
    if test -f cursor-agent; then
      cp cursor-agent $out/share/cursor-agent/
    elif test -f dist-package/cursor-agent; then
      cp dist-package/cursor-agent $out/share/cursor-agent/
    else
      echo "ERROR: cursor-agent binary not found in tarball" >&2
      echo "Expected either ./cursor-agent or ./dist-package/cursor-agent" >&2
      ls -la >&2
      exit 1
    fi

    ln -s $out/share/cursor-agent/cursor-agent $out/bin/cursor-agent

    runHook postInstall
  '';

  meta = {
    description = "Cursor CLI";
    homepage = "https://cursor.com/cli";
    license = lib.licenses.unfree;
    mainProgram = "cursor-agent";
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}