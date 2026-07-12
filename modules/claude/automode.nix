# Claude Code auto-mode classifier configuration.
#
# Imported by programs.claude.autoMode in claude-config.nix and read by
# Claude's auto-mode classifier as prose rules. Each field is a list of
# natural-language strings; `$defaults` inherits Claude Code's built-in
# rules at that position. Reference:
# https://code.claude.com/docs/en/auto-mode-config.
#
#   environment - trusted-infrastructure context, so routine cross-repo,
#                 cross-org, cloud, and homelab actions are not flagged
#                 as exfiltration.
#   allow       - exceptions that auto-permit actions the default
#                 soft-block list would otherwise stop.
#   soft_deny   - destructive actions that need explicit user intent or
#                 an `allow` exception before proceeding.
#
# All values come from the maintainer profile (modules/maintainer-profile.nix):
# the trusted orgs are derived from `userConfig.user.{fullName,trustedOrgs}`,
# and the homelab/day-job context is appended only when `userConfig.homelab`
# is enabled — so a fresh consumer gets a neutral classifier.
{ userConfig, lib }:
let
  ghUser = userConfig.user.fullName;
  trustedOrgs = userConfig.user.trustedOrgs or [ ];
  homelab = userConfig.homelab or { };
  orgsClause = lib.concatMapStringsSep " and " (org: "github.com/${org}/*") (
    [ ghUser ] ++ trustedOrgs
  );
in
{
  environment = [
    "$defaults"
    "Source control: GitHub orgs ${orgsClause}. All public repos under these are trusted to clone, push, branch, and PR-mutate against. Force-push to feature branches is routine; force-push to main is off-limits."
  ]
  ++ lib.optionals (homelab.enable or false) (homelab.environmentRules or [ ]);

  allow = [
    "$defaults"
    "Running `rm` to delete files inside the current working repository is routine and safe — allow without confirmation, including recursive deletion of ordinary subdirectories such as build outputs, caches, vendored dependencies, test fixtures, and git worktrees."
    "Running inline interpreters for read-only inspection — `python -c`, `python3 -c`, `node -e`, `ruby -e`, `perl -e` — to parse JSON, read a config file, or compute and print a value is routine and safe; allow without confirmation. Only require confirmation when such a one-liner writes or deletes files, or sends data to a destination outside the working repository."
    "Read-only compound shell chains that combine already-safe inspection tools (cd, ls, cat, head, tail, wc, sort, uniq, grep, rg, jq, `sed -n`, `awk` print, `find` without -delete/-exec, and git status/log/diff/show) with `&&` or `|` are routine and safe; allow without confirmation even though the combined command does not match a single narrow allow rule."
  ];

  soft_deny = [
    "$defaults"
    "Require confirmation before a forced or recursive `rm` that could be catastrophic: deleting the entire working repository, removing any path outside the current repo, or wiping large or untracked directory trees. Deleting individual files or ordinary subdirectories inside the repo does not need confirmation."
  ];
}
