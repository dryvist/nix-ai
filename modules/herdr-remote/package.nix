# herdr-remote's relay, packaged.
#
# Upstream (dcolinmorgan/herdr-remote) ships no setup.py, no lockfile and no
# nixpkgs entry — it is run as `uv run relay/herdr_relay.py`, with dependencies
# declared in a PEP 723 inline block at the top of that file. uv resolves them
# from the network at start time, which a guest built from a pinned flake must
# not do. So the dependency list is transcribed here from that block and
# supplied by nixpkgs instead:
#
#   requires-python = ">=3.10"
#   dependencies = ["websockets>=14.0", "zeroconf>=0.80.0",
#                   "pywebpush>=2.0.0", "py-vapid>=1.9.0"]
#
# A TRANSCRIBED LIST ROTS. If upstream adds a dependency the relay fails at
# RUNTIME with ModuleNotFoundError — on the guest, after the closure is already
# deployed. The `herdr-remote-pep723-deps` check in flake/checks.nix re-parses
# the block from the pinned source and fails the build when the two disagree,
# so the drift surfaces on the controller instead.
#
# The whole relay/ directory is installed, not just herdr_relay.py: the script
# loads agent_state.py and transcript.py by path relative to its own __file__,
# with an importlib fallback that would silently pick up the wrong copy if the
# siblings were missing.
{
  lib,
  stdenvNoCC,
  python3,
  openssh,
  makeWrapper,
  src,
}:

let
  # Transcribed from the PEP 723 block above. Declared ONCE, here, and re-used
  # by the herdr-remote-pep723-deps check in flake/checks.nix, which re-parses
  # that block from the pinned source and fails if the two disagree. Every
  # name happens to be identical in nixpkgs; if upstream ever adds one that is
  # not, map it here and the check will point at the mismatch.
  pep723Deps = [
    "websockets"
    "zeroconf"
    "pywebpush"
    "py-vapid"
  ];

  pythonEnv = python3.withPackages (ps: map (n: ps.${n}) pep723Deps);
in
stdenvNoCC.mkDerivation {
  pname = "herdr-remote-relay";
  version = "0-unstable-2026-09-01";
  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/herdr-remote
    cp -r relay/. $out/libexec/herdr-remote/

    # ssh is on PATH because the relay drives every herdr runtime over SSH —
    # it never speaks to a socket directly. Without it the dashboard renders an
    # empty fleet rather than erroring, which is the failure this whole guest
    # is supposed to make visible.
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/herdr-remote-relay \
      --add-flags $out/libexec/herdr-remote/herdr_relay.py \
      --prefix PATH : ${lib.makeBinPath [ openssh ]}

    runHook postInstall
  '';

  passthru = { inherit pep723Deps; };

  meta = {
    description = "Relay and web dashboard for driving herdr runtimes over SSH";
    homepage = "https://github.com/dcolinmorgan/herdr-remote";
    mainProgram = "herdr-remote-relay";
    platforms = lib.platforms.linux;
  };
}
