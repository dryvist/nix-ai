# session-archive module regression tests
#
# The invariants here are invisible in normal use — a regression re-uploads the
# whole corpus every night (store ListObjectsV2 truncation) or quietly ships
# credentials to the bucket, rather than failing loudly.
{
  pkgs,
  hmConfig,
  hmConfigSessionArchive,
  hmConfigSessionArchiveSessionEnd,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs.lib) hasInfix;
  inherit (pkgs.lib) splitString;
  # Read the script as code only: comments explain the forbidden whole-tree
  # sync, and a naive scan would match the very prose that bans it.
  code = pkgs.lib.concatStringsSep "\n" (
    builtins.filter (l: builtins.match "[[:space:]]*#.*" l == null) (
      pkgs.lib.splitString "\n" (builtins.readFile ../../modules/scripts/session-archive.sh)
    )
  );
  lockToken = "\"$flock_bin\" -n 9 || exit 0";
  guardToken = "if (( stamp_mtime > 0 && now - stamp_mtime < min_interval_seconds )); then";
  stampToken = "touch \"$stamp_file\"";
  credentialToken = "exec \"$nice_bin\" -n 10 \"$timeout_bin\"";
  lockOffset = builtins.stringLength (builtins.head (splitString lockToken code));
  guardOffset = builtins.stringLength (builtins.head (splitString guardToken code));
  stampOffset = builtins.stringLength (builtins.head (splitString stampToken code));
  credentialOffset = builtins.stringLength (builtins.head (splitString credentialToken code));
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
      cfg.trigger == "schedule" || throw "session-archive must default to the launchd schedule trigger";
    assert
      cfg.maxRunHours == 11 && cfg.minIntervalHours == 20
      || throw "session-archive runtime and interval defaults must remain 11 and 20 hours";
    assert
      hmConfigSessionArchive.config.launchd.agents ? session-archive
      || throw "session-archive schedule trigger must define its launchd agent";
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
    # The store returns 503 and 504 in bursts; the CLI default of 2 retries fails whole leaf syncs.
    assert
      hasInfix "export AWS_RETRY_MODE=standard AWS_MAX_ATTEMPTS=10" code
      || throw "session-archive must set standard AWS CLI retries so storage error bursts do not fail a sync";
    # Symlinks inside these dirs point into this machine's /nix/store.
    assert
      hasInfix "--no-follow-symlinks" code
      || throw "session-archive must pass --no-follow-symlinks, or it uploads this machine's store contents";
    assert
      builtins.all (c: builtins.elem c cfg.excludes) creds
      || throw "session-archive must exclude every credential pattern; backup must not place secrets in a bucket";
    # A multi-gigabyte upload times out and takes the next few uploads down with it.
    assert
      builtins.elem "*thread_history_*.sqlite" cfg.excludes
      || throw "session-archive must exclude the rollout-derived thread history database";
    builtins.deepSeq agent (
      helpers.mkMarker "check-session-archive-agent" "session-archive: per-leaf sync, no symlink follow, credentials excluded"
    );

  session-archive-session-end =
    let
      hm = hmConfigSessionArchiveSessionEnd.config;
      events = hm.programs.claude.hooks.events.SessionEnd or [ ];
      commands = pkgs.lib.concatMap (event: map (hook: hook.command or "") (event.hooks or [ ])) events;
    in
    assert
      !(hm.launchd.agents ? session-archive)
      || throw "session-end trigger must not define a launchd agent";
    assert
      events != [ ]
      && builtins.any (
        command:
        hasInfix "nohup" command && hasInfix "</dev/null" command && hasInfix "session-end-hook.log" command
      ) commands
      || throw "session-end trigger must register a detached SessionEnd hook with log output";
    helpers.mkMarker "check-session-archive-session-end" "session-archive: detached SessionEnd hook without a launchd agent";

  session-archive-credential-guard =
    assert
      hasInfix lockToken code
      && hasInfix guardToken code
      && hasInfix stampToken code
      && hasInfix credentialToken code
      || throw "session-archive session-end wrapper must check and touch its interval stamp before invoking the credential command";
    assert
      lockOffset < guardOffset && guardOffset < stampOffset && stampOffset < credentialOffset
      || throw "session-archive session-end wrapper must check its interval stamp and touch it before invoking the credential command";
    helpers.mkMarker "check-session-archive-credential-guard" "session-archive: interval guard precedes the credential command";

  session-archive-negative =
    assert
      !(hmConfig.config.launchd.agents ? session-archive)
      || throw "session-archive agent must NOT exist when programs.sessionArchive.enable = false (default)";
    helpers.mkMarker "check-session-archive-negative" "session-archive agent correctly absent when disabled";
}
