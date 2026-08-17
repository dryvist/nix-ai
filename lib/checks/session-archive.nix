# session-archive module regression tests
#
# The invariants here are invisible in normal use — a regression re-uploads the
# whole corpus every night (store ListObjectsV2 truncation) or quietly ships
# credentials to the bucket, rather than failing loudly.
{
  pkgs,
  hmConfig,
  hmConfigSessionArchive,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs.lib) hasInfix;
  # Read the script as code only: comments explain the forbidden whole-tree
  # sync, and a naive scan would match the very prose that bans it.
  code = pkgs.lib.concatStringsSep "\n" (
    builtins.filter (l: builtins.match "[[:space:]]*#.*" l == null) (
      pkgs.lib.splitString "\n" (builtins.readFile ../../modules/scripts/session-archive.sh)
    )
  );
in
{
  session-archive-agent =
    let
      cfg = hmConfigSessionArchive.config.programs.sessionArchive;
      agent = hmConfigSessionArchive.config.launchd.agents.session-archive.config;
      cal = builtins.head agent.StartCalendarInterval;
      creds = [
        "*.credentials.json"
        "*auth.json"
        "*oauth_creds.json"
        "*antigravity-oauth-token"
      ];
    in
    assert
      cal.Hour == cfg.calendarHour && cal.Minute == cfg.calendarMinute
      || throw "session-archive agent must schedule from calendarHour/calendarMinute";
    # Per-leaf iteration is the whole point of the script: the store truncates
    # ListObjectsV2 on large parent prefixes, so a whole-tree sync re-uploads
    # tens of thousands of already-present objects every run.
    assert
      hasInfix "maxdepth 1" code
      || throw "session-archive must iterate depth-1 subdirectories (per-leaf sync)";
    assert
      !hasInfix "s3 sync \"$src/\"" code
      || throw "session-archive must never whole-tree sync a vendor dir: ListObjectsV2 truncation re-uploads the entire corpus";
    # Symlinks inside these dirs point into this machine's /nix/store.
    assert
      hasInfix "--no-follow-symlinks" code
      || throw "session-archive must pass --no-follow-symlinks, or it uploads this machine's store contents";
    assert
      builtins.all (c: builtins.elem c cfg.excludes) creds
      || throw "session-archive must exclude every credential pattern; backup must not place secrets in a bucket";
    helpers.mkMarker "check-session-archive-agent" "session-archive: per-leaf sync, no symlink follow, credentials excluded";

  session-archive-negative =
    assert
      !(hmConfig.config.launchd.agents ? session-archive)
      || throw "session-archive agent must NOT exist when programs.sessionArchive.enable = false (default)";
    helpers.mkMarker "check-session-archive-negative" "session-archive agent correctly absent when disabled";
}
