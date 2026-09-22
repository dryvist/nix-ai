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

    # Upstream PR not yet open (splunk/token-meter, no write access from this
    # identity yet); tracked in Vikunja 3416. Fixes the `stats` MCP query
    # scanning full session history regardless of the requested start/end
    # window, which timed out even on narrow (e.g. 2-day) queries.
    patches = [ ./patches/token-meter-stats-prefilter.patch ];

    dontBuild = true;

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      # $PWD is the patched, unpacked source tree (patchPhase already ran).
      # Run the module this patch touches, not the full upstream suite:
      # tests/test_meter.py::test_docs_explain_pi_evidence_and_privacy_boundaries
      # fails on unpatched upstream main too (README/test doc drift,
      # unrelated to this change) and isn't something to silently paper
      # over here.
      python3 -m unittest tests.test_mcp_queries
      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall

      ${pkgs.bash}/bin/bash ${../scripts/package-token-meter.sh} "$PWD" "$out/share/token-meter"

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
