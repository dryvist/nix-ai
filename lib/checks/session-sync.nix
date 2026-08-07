# session-sync module regression tests
#
# Three properties make this safe to run against a machine that is also being
# worked on, and all three are invisible in normal use — a regression would
# quietly destroy history rather than fail loudly.
{
  pkgs,
  hmConfig,
  hmConfigSessionSync,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  # Read the script as code only. The comments explain why --delete is absent,
  # and a naive scan of the whole file matches that prose and fails on the very
  # explanation of the rule it is enforcing.
  code = pkgs.lib.concatStringsSep "\n" (
    builtins.filter (l: builtins.match "[[:space:]]*#.*" l == null) (
      pkgs.lib.splitString "\n" (builtins.readFile ../../modules/scripts/session-sync.sh)
    )
  );
in
{
  session-sync-agent =
    let
      cfg = hmConfigSessionSync.config.programs.sessionSync;
      args = hmConfigSessionSync.config.launchd.agents.session-sync.config.ProgramArguments;
      creds = [
        ".credentials.json"
        "auth.json"
        "oauth_creds.json"
        "antigravity-oauth-token"
      ];
    in
    assert
      builtins.elem cfg.remote args || throw "session-sync agent must pass the remote to the script";
    # Losing --update means this machine's older copy overwrites a session that
    # was resumed on the peer; losing the absence of --delete means the peer's
    # own sessions are removed because they are not present here.
    assert
      builtins.match ".*--update.*" code != null
      || throw "session-sync must pass rsync --update, or a session resumed on the peer is reverted by this machine's older copy";
    assert
      builtins.match ".*--delete.*" code == null
      || throw "session-sync must never pass rsync --delete: the peer's own sessions are not ours to remove";
    # Every symlink in these directories is home-manager config pointing into
    # this machine's store, which is meaningless on the peer.
    assert
      builtins.match ".*--no-links.*" code != null
      || throw "session-sync must pass rsync --no-links, or it copies this machine's /nix/store symlinks over the peer's own home-manager config";
    assert
      builtins.all (c: builtins.elem c cfg.excludes) creds
      || throw "session-sync must exclude every credential file; syncing history must not place secrets on a second host";
    helpers.mkMarker "check-session-sync-agent" "session-sync: update-only, non-deleting, credentials excluded";

  session-sync-negative =
    assert
      !(hmConfig.config.launchd.agents ? session-sync)
      || throw "session-sync agent must NOT exist when programs.sessionSync.enable = false (default)";
    helpers.mkMarker "check-session-sync-negative" "session-sync agent correctly absent when disabled";
}
