#!/usr/bin/env python3
"""Scan shell scripts for constructs Apple's bash 3.2 cannot parse or run.

WHY THIS EXISTS. Every launchd agent in this module whose payload is a shell
script is launched as `/bin/bash <script>` on purpose — a Nix interpreter
anywhere in the chain becomes the responsible process and loses the TCC grant
that lets the cluster probe its peer at all (see modules/mlx/options-launch.nix).
The price of that convention is that the scripts must parse under the bash
3.2.57 Apple ships, and nothing enforced it.

The failure it caught (2026-07-25, live): `repair_link_direct` used a `case`
statement INSIDE a `$( ... )` command substitution. bash 3.2's parser terminates
the substitution at the first `)` of the case pattern, so under Apple bash the
snippet raised `syntax error near unexpected token 'newline'`, exited 0, and
substituted a garbage string where a device name was expected. bash 5 parses it
correctly, so every local test and every check that ran under the Nix shebang
passed. Silent, and only ever wrong in production.

Detected here:
  * a `case` keyword inside `$( ... )`             (the 3.2 parser bug above)
  * associative arrays (`declare -A` / `local -A`) (bash 4)
  * `mapfile` / `readarray`                        (bash 4)
  * `${var^^}` / `${var,,}` case modification      (bash 4)
  * `|&` pipe-with-stderr and `coproc`             (bash 4)
  * `local -n` nameref                             (bash 4.3)

Usage: bash32-scan.py FILE [FILE...]  — exits non-zero and prints every finding.
"""

import re
import sys

BASH4 = [
    (re.compile(r"(^|[;&|(\s])(declare|typeset|local)\s+-[A-Za-z]*A"), "associative array (declare -A) needs bash 4"),
    (re.compile(r"(^|[;&|(\s])(mapfile|readarray)\s"), "mapfile/readarray needs bash 4"),
    (re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(\^\^|,,)"), "${var^^} / ${var,,} needs bash 4"),
    (re.compile(r"\|&"), "|& (pipe stderr) needs bash 4"),
    (re.compile(r"(^|[;&|(\s])coproc\s"), "coproc needs bash 4"),
    (re.compile(r"(^|[;&|(\s])local\s+-[A-Za-z]*n\s"), "local -n nameref needs bash 4.3"),
]

CASE_WORD = re.compile(r"case\Z")


def scan_case_in_substitution(text):
    """Yield (line, message) for each `case` keyword inside a $( ... ).

    Character scanner tracking quote state and $(-nesting. A `case` seen while
    the $(-depth is non-zero is reported; we stop tracking parens after that
    point for the region only in the sense that the report is already made, so
    a mis-balanced pattern paren cannot suppress a finding already emitted.
    """
    findings = []
    line = 1
    i = 0
    n = len(text)
    depth = 0          # $( ... ) nesting depth
    # stack entries: (is_command_substitution, enclosing_double_quote_state).
    # A $( ... ) starts a fresh quoting context — `"$(cat "$1")"` is three
    # separate quote regions, not one — so the enclosing state is saved and
    # restored rather than toggled straight through.
    parens = []
    in_squote = False
    in_dquote = False
    word = ""
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            word = ""
            i += 1
            continue
        if in_squote:
            if c == "'":
                in_squote = False
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if c == "#" and not in_dquote and word == "":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "'" and not in_dquote:
            in_squote = True
            i += 1
            continue
        if c == '"':
            in_dquote = not in_dquote
            i += 1
            continue
        if c == "$" and i + 1 < n and text[i + 1] == "(":
            # $(( arithmetic )) is not a command substitution
            if i + 2 < n and text[i + 2] == "(":
                i += 3
                continue
            parens.append((True, in_dquote))
            in_dquote = False
            depth += 1
            i += 2
            word = ""
            continue
        if c == "(" and not in_dquote:
            parens.append((False, in_dquote))
            i += 1
            word = ""
            continue
        if c == ")" and not in_dquote:
            if parens:
                was_subst, saved_dquote = parens.pop()
                if was_subst:
                    depth -= 1
                    in_dquote = saved_dquote
            i += 1
            word = ""
            continue
        if c.isalnum() or c == "_":
            word += c
            if depth > 0 and word == "case":
                nxt = text[i + 1] if i + 1 < n else " "
                if not (nxt.isalnum() or nxt == "_"):
                    findings.append(
                        (line, "`case` inside $( ... ) — bash 3.2 mis-parses this "
                               "and silently substitutes garbage; move it into a "
                               "function defined at top level, or use the `(pattern)` form")
                    )
        else:
            word = ""
        i += 1
    return findings


def main(argv):
    failures = []
    for path in argv:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for line, msg in scan_case_in_substitution(text):
            failures.append(f"{path}:{line}: {msg}")
        for lineno, raw in enumerate(text.splitlines(), start=1):
            stripped = raw.split("#", 1)[0] if raw.lstrip().startswith("#") else raw
            for pattern, msg in BASH4:
                if pattern.search(stripped):
                    failures.append(f"{path}:{lineno}: {msg}: {raw.strip()}")
    if failures:
        sys.stderr.write(
            "bash 3.2 compatibility scan FAILED — these agents are launched by "
            "Apple's /bin/bash (modules/mlx/options-launch.nix):\n"
        )
        for f in failures:
            sys.stderr.write("  " + f + "\n")
        return 1
    sys.stderr.write(f"bash 3.2 compatibility scan: {len(argv)} file(s) clean\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
