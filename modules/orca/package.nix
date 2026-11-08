{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation rec {
  pname = "orca";
  # renovate: datasource=github-releases depName=stablyai/orca
  version = "1.4.245";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-macos-arm64.dmg";
    hash = "sha256-pBO2WZiSawpGVNa34MD3iaX3WK06d3o97GDI3nIrutg=";
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  # Fixup's patchShebangs rewrites scripts inside the signed bundle and breaks its code signature.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R Orca.app "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Orca desktop application";
    homepage = "https://github.com/stablyai/orca";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
