# Cursor Formatter
#
# Maps the shared permission engine onto Cursor CLI permission tokens
# (~/.cursor/cli-config.json `permissions.allow` / `permissions.deny`).
#
# Cursor has no "ask" tier — anything not in `allow` either prompts
# (approvalMode = allowlist) or routes through the auto-review classifier
# (approvalMode = auto-review). Ask-listed commands are therefore left
# unlisted so they keep requiring a human decision, matching the shared
# engine's semantics.
#
# Token shapes (https://cursor.com/docs/cli/reference/permissions):
#   Shell(cmd)   — command match against the first token + args
#   Read(glob)   — file read allow/deny
#   Write(glob)  — file write allow/deny
#   WebFetch(domain) — domain allow for the web-fetch tool
#
# Deny always wins at runtime. Shell-only metacharacters that would confuse
# the matcher force a skip, mirroring the codex formatter's
# representability filter.
{ lib, flattenCommands }:

let
  representable =
    cmd:
    let
      tokens = lib.filter (token: token != "") (lib.splitString " " cmd);
      tokenOk =
        token:
        !(lib.any (char: lib.hasInfix char token) [
          "*"
          "?"
          "<"
          ">"
          "|"
          "&"
          ";"
          "$"
          "("
          ")"
          "{"
          "}"
          "\""
          "'"
          "\\"
          "`"
          "~"
        ]);
    in
    tokens != [ ] && lib.all tokenOk tokens;

  supportedCommands = cmds: lib.filter representable cmds;

  shellTokens = cmds: lib.map (cmd: "Shell(${cmd})") (supportedCommands cmds);
in
{
  formatPermission =
    permissions:
    let
      allowCommands = flattenCommands permissions.allow;
      denyCommands = flattenCommands permissions.deny;
    in
    {
      allow =
        shellTokens allowCommands ++ lib.map (domain: "WebFetch(${domain})") permissions.webfetchDomains;
      deny =
        shellTokens denyCommands
        ++ lib.concatMap (pattern: [
          "Read(${pattern})"
          "Write(${pattern})"
        ]) permissions.denyPatterns;
    };
}
