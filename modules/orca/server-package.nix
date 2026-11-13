{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation rec {
  pname = "orca-server";
  # renovate: datasource=github-releases depName=stablyai/orca
  version = "1.4.258";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-server-linux-x64.tar.gz";
    hash = "sha256-/X8j9ftv5D+ymC0XQ413L6x8xlyCCKIS0P+yJLUE4xE=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  # Libraries the bundled Node runtime and its native addons link against.
  buildInputs = [ stdenv.cc.cc.lib ];

  sourceRoot = "orca-server-${version}-linux-x64";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/orca-server" "$out/bin"
    cp -R . "$out/lib/orca-server"
    # The launcher resolves its own real path before finding the bundled runtime, so a symlink to it is enough.
    ln -s "$out/lib/orca-server/bin/orca-ide" "$out/bin/orca"
    runHook postInstall
  '';

  meta = {
    description = "Headless Orca server (orca serve)";
    mainProgram = "orca";
    homepage = "https://github.com/stablyai/orca";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
