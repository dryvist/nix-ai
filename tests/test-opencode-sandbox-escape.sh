#!/usr/bin/env bash
# Live probes for the OpenCode Seatbelt profile (modules/opencode/opencode.sb), run on
# macOS, where sandbox-exec is the enforcement point. Elsewhere the script exits 2 and
# reports nothing as passed.
#
# Each attack probe runs inside the profile in a fresh standalone clone under a temp
# work root and PASSES when its write does not get through. When a write does get
# through, trusted git runs in that clone and the probe reports whether a planted
# core.fsmonitor command ran. Control probes PASS when their write goes through. A
# probe whose body never started is a FAIL, so a broken probe cannot read as a pass.
#
# Usage: OPENCODE_BIN=/path/to/opencode tests/test-opencode-sandbox-escape.sh [opencode.sb]
#
# OPENCODE_BIN is the real binary, for the FSEvents row. The launcher on PATH refuses
# work roots outside its configured one, so it cannot run here.
set -u

if [ "$(uname -s)" != Darwin ]; then
  echo "opencode-sandbox-escape: needs macOS sandbox-exec; nothing was tested" >&2
  exit 2
fi

source_profile="${1:-$(dirname "$0")/../modules/opencode/opencode.sb}"
root="$(realpath "$(mktemp -d)")"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/tmp" "$root/work"

# Render the profile as sandbox.nix does: the home directory, and no extra ports.
profile="$root/opencode.sb"
sed -e "s|@HOME@|$HOME|g" -e '/@LOCAL_PORTS@/d' "$source_profile" >"$profile"

# Fixtures and sandboxed git share this identity and never read the user's git config,
# so no commit here can reach the signing key (a signing prompt would stall the run).
git_env=(GIT_AUTHOR_NAME=probe GIT_AUTHOR_EMAIL=probe@example.invalid
  GIT_COMMITTER_NAME=probe GIT_COMMITTER_EMAIL=probe@example.invalid
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)
export "${git_env[@]}"
git -c init.defaultBranch=main init -q "$root/src"
git -C "$root/src" commit -q --allow-empty -m init

fails=0
total=0
report() { # status name detail
  total=$((total + 1))
  printf '%-4s %-26s %s\n' "$1" "$2" "$3"
  [ "$1" = PASS ] || fails=$((fails + 1))
}

# A standalone clone (its own .git directory), created outside the sandbox. mktemp makes
# the directory name unique: names that differ only in case share one directory on the
# case-insensitive temp volume.
fresh() { # name -> clone path
  local dir
  dir="$(mktemp -d "$root/work/$1.XXXXXX")" && git clone -q --no-hardlinks "$root/src" "$dir" && printf '%s' "$dir"
}

# The one sandbox-exec invocation: environment allowlist, work root and temp directory.
# Fills sbx with the command prefix.
sandbox_argv() { # clone
  sbx=(/usr/bin/env -i HOME="$HOME" USER="${USER:-}" PATH="$PATH" TERM=dumb
    TMPDIR="$root/tmp" MARK="$root/marker" "${git_env[@]}"
    /usr/bin/sandbox-exec -D WORKTREE="$1" -D TMPDIR="$root/tmp" -f "$profile")
}

# Runs a body inside the profile with the clone as the work root.
sandboxed() { # clone body
  sandbox_argv "$1"
  "${sbx[@]}" /bin/bash -c "cd \"\$0\" || exit 99; $2" "$1" >"$root/last.log" 2>&1
}

# Attack: PASS unless the body reaches its ATTACK-OK line. START proves it ran.
attack() { # name body
  local clone detail
  clone="$(fresh "$1")" || { report FAIL "$1" "clone failed"; return; }
  sandboxed "$clone" "echo START; $2"
  if ! grep -q '^START$' "$root/last.log"; then
    report FAIL "$1" "probe did not run: $(head -c 120 "$root/last.log" | tr '\n' ' ')"
  elif grep -q '^ATTACK-OK$' "$root/last.log"; then
    git -C "$clone" status --porcelain >/dev/null 2>&1
    if [ -e "$root/marker" ]; then detail="trusted git status ran the payload"; else detail="payload did not run"; fi
    report FAIL "$1" "write got through; $detail"
    rm -f "$root/marker"
  else
    report PASS "$1" "stopped: $(grep -v -e '^START$' -e 'current directory' "$root/last.log" | head -1 | cut -c1-90)"
  fi
}

# Control: PASS only when the body reaches its OK line.
expect_ok() { # name body
  local clone
  clone="$(fresh "$1")" || { report FAIL "$1" "clone failed"; return; }
  sandboxed "$clone" "echo START; $2"
  if grep -q '^OK$' "$root/last.log"; then
    report PASS "$1" "allowed"
  else
    report FAIL "$1" "blocked: $(head -c 120 "$root/last.log" | tr '\n' ' ')"
  fi
}

# The FSEvents row starts first, so its 60 seconds overlap the probes. It has its own
# clone and log. perl's alarm ends the exact process it execs, which is $!.
fsevents_start() {
  if [ ! -x "${OPENCODE_BIN:-/nonexistent}" ]; then
    fsevents_skip="OPENCODE_BIN is not set to the real opencode binary"
  elif ! fsevents_clone="$(fresh opencode-run)"; then
    fsevents_skip="clone failed"
  else
    fsevents_log="$root/opencode-run.log"
    sandbox_argv "$fsevents_clone"
    perl -e 'chdir shift or die "chdir: $!"; alarm shift; exec @ARGV' "$fsevents_clone" 60 \
      "${sbx[@]}" "$OPENCODE_BIN" run --print-logs -m litellm/default "say ok" >"$fsevents_log" 2>&1 &
    fsevents_pid=$!
  fi
}

# Passes when the run got past the FSEvents start: no sandbox denial of the lookup for
# its PID, no start error printed, and the run reached the model call.
fsevents_finish() {
  if [ -n "${fsevents_skip:-}" ]; then
    report FAIL opencode-run-fsevents "$fsevents_skip"
    return
  fi
  wait "$fsevents_pid"
  if grep -q 'Error starting FSEvents stream' "$fsevents_log"; then
    report FAIL opencode-run-fsevents "FSEvents start error printed"
    return
  fi
  denied="$(log show --last 10m --predicate 'eventMessage CONTAINS "mach-lookup com.apple.FSEvents"' \
    --style compact 2>/dev/null | grep -c "($fsevents_pid)")"
  if [ "$denied" -gt 0 ]; then
    report FAIL opencode-run-fsevents "sandbox denied the FSEvents lookup for pid $fsevents_pid"
  elif ! grep -q 'llm runtime selected' "$fsevents_log"; then
    report FAIL opencode-run-fsevents "run did not reach the model call: $(tail -1 "$fsevents_log" | cut -c1-90)"
  else
    report PASS opencode-run-fsevents "past FSEvents start; no FSEvents denial for pid $fsevents_pid"
  fi
}

payload='printf "[core]\n\tfsmonitor = /usr/bin/touch %s\n" "$MARK"'

fsevents_start

# The .git entry itself: rename, remove, recreate, and nested creation.
attack rename-git-dir "mv .git .gitx && echo ATTACK-OK"
attack rename-GIT-case "mv .GIT .gitx && echo ATTACK-OK"
attack gitfile-after-removal "rm -rf .git 2>/dev/null; [ ! -e .git ] && printf 'gitdir: .gitx\n' >.git && echo ATTACK-OK"
attack create-nested-git "mkdir sub && git -C sub init -q && echo ATTACK-OK"

# Config and hook files, under the names the sandbox might see them by.
attack write-gitx-config "mkdir -p .gitx && $payload >.gitx/config && echo ATTACK-OK"
attack write-git-config "$payload >>.git/config && echo ATTACK-OK"
attack unlink-git-config "rm .git/config && echo ATTACK-OK"
attack rename-into-git-config "printf 'x\n' >src-file && mv src-file .git/config && echo ATTACK-OK"
attack write-git-config-worktree "$payload >.git/config.worktree && echo ATTACK-OK"
attack write-git-hook "printf '#!/bin/sh\n' >.git/hooks/fsmonitor-watchman && echo ATTACK-OK"
attack write-GIT-config-case "$payload >>.GIT/config && echo ATTACK-OK"
attack write-submodule-config "mkdir -p .git/modules/x && $payload >.git/modules/x/config && echo ATTACK-OK"
attack hardlink-to-git-config "ln .git/config cfg-alias && $payload >>cfg-alias && echo ATTACK-OK"
attack symlink-to-git-config "ln -s .git/config cfg-link && $payload >>cfg-link && echo ATTACK-OK"
attack symlink-dir-to-hooks "ln -s .git/hooks hk && printf '#!/bin/sh\n' >hk/fsmonitor-watchman && echo ATTACK-OK"

# Agent instruction files and directories that a later trusted session would load.
for name in CLAUDE.md claude.md AGENTS.md GEMINI.md; do
  attack "write-$name" "printf 'x\n' >$name && echo ATTACK-OK"
done
attack write-cursor-dir "mkdir -p .cursor && printf 'x\n' >.cursor/rules && echo ATTACK-OK"
attack write-CLAUDE-dir-case "mkdir -p .CLAUDE && printf '{}\n' >.CLAUDE/settings.json && echo ATTACK-OK"

# Controls: the work root stays writable, and a normal commit still works.
expect_ok control-write-file "printf 'x\n' >ok.txt && echo OK"
expect_ok control-git-status "git status --porcelain >/dev/null && echo OK"
expect_ok control-commit-inside-clone "printf 'probe\n' >probe.txt && git add probe.txt && git commit -q -m probe && git log -1 --format=%s | grep -qx probe && echo OK"

fsevents_finish

echo "$total probes, $fails failed"
[ "$fails" -eq 0 ]
