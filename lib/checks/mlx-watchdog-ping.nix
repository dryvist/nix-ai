# hc_ping() deadman contract: every url listed in the healthcheck file is
# pinged, comments and blanks are skipped, one unreachable monitor does not
# stop the others. Kept apart from mlx-watchdog.nix, which exercises the
# busy-progress ladder with its own richer curl fake.
{ pkgs, src }:
let
  # Appends the requested url to $FAKE_PING_LOG; a url naming "down" fails the
  # way an unreachable monitor would.
  fakeCurl = pkgs.writeShellScriptBin "curl" ''
    url="''${@: -1}"
    printf '%s\n' "$url" >> "$FAKE_PING_LOG"
    case "$url" in *down*) exit 1 ;; esac
  '';
in
{
  mlx-watchdog-hc-ping = pkgs.runCommand "check-mlx-watchdog-hc-ping" {
    nativeBuildInputs = [
      fakeCurl
      pkgs.gnused
    ];
    WATCHDOG = "${src}/modules/mlx/scripts/mlx-watchdog.sh";
  } (builtins.readFile ../../tests/hc-ping-test.sh);
}
