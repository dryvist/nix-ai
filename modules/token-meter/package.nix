{
  lib,
  pkgs,
  token-meter-src,
}:
let
  runtime = pkgs.stdenvNoCC.mkDerivation {
    pname = "token-meter-runtime";
    version = token-meter-src.shortRev or "main";
    src = token-meter-src;

    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.python3
    ];

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      ${pkgs.bash}/bin/bash ${../scripts/package-token-meter.sh} "$src" "$out/share/token-meter"

      mkdir -p "$out/bin"
      makeWrapper ${lib.getExe pkgs.python3} "$out/bin/token-meter-server" \
        --add-flags "$out/share/token-meter/meter.py" \
        --set PYTHONPATH "$out/share/token-meter" \
        --prefix PATH : ${lib.makeBinPath [ pkgs.git ]}
      makeWrapper ${lib.getExe pkgs.python3} "$out/bin/token-meter-mcp" \
        --add-flags "$out/share/token-meter/token_meter_mcp.py" \
        --set PYTHONPATH "$out/share/token-meter" \
        --prefix PATH : ${lib.makeBinPath [ pkgs.git ]}

      runHook postInstall
    '';
  };

  menuBar = pkgs.stdenv.mkDerivation {
    pname = "token-meter-menubar";
    version = token-meter-src.shortRev or "main";
    src = token-meter-src;

    nativeBuildInputs = [ pkgs.swift ];

    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      swiftc menubar/TokenMeterMenuBar.swift -o token-meter-menubar
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      app="$out/Applications/Token Meter Menu Bar.app/Contents"
      mkdir -p "$app/MacOS"
      install -m755 token-meter-menubar "$app/MacOS/token-meter-menubar"
      install -m644 menubar/Info.plist "$app/Info.plist"
      runHook postInstall
    '';
  };
in
{
  inherit menuBar runtime;
}
