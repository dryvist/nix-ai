#!/usr/bin/env bash
# Launches OpenCode under the Seatbelt profile. sandbox.nix fills the placeholders.

refuse() {
  echo "opencode: refusing to run: $1" >&2
  exit 1
}

home_dir=@HOME@
work_root="$(realpath -m @WORK_ROOT@)"

# The worktree is the git toplevel of the cwd: a standalone clone under the work root.
top="$(git rev-parse --show-toplevel 2>/dev/null)" ||
  refuse "not inside a git repository; clone the project under $work_root first"
worktree="$(realpath "$top")"
case "$worktree" in
  / | "$home_dir") refuse "$worktree is not a project directory" ;;
esac
# A worktree above the home directory would make the home directory writable.
case "$home_dir/" in
  "$worktree/"*) refuse "$worktree contains the home directory" ;;
esac
case "$worktree/" in
  "$work_root/"?*) ;;
  *) refuse "$worktree is outside the work root $work_root" ;;
esac

# A linked worktree shares refs and objects with another repository, so only a
# standalone clone (its own .git directory) is accepted.
git_common="$(git rev-parse --git-common-dir 2>/dev/null)" ||
  refuse "cannot resolve the git common directory of $worktree"
if [ "$(realpath "$git_common")" != "$worktree/.git" ]; then
  refuse "$worktree is a linked worktree; use a standalone clone under $work_root"
fi

# A private temp directory per run, removed when the run ends. The shared per-user
# temp directory stays outside the sandbox.
cache_dir="$home_dir/.cache/opencode"
mkdir -p "$cache_dir"
tmpdir="$(realpath "$(mktemp -d "$cache_dir/tmp.XXXXXX")")"
trap 'rm -rf "$tmpdir"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Allowlist only. Credentials in the caller's shell never reach OpenCode.
envargs=("TMPDIR=$tmpdir")
for name in HOME USER LOGNAME PATH TERM COLORTERM LANG SHELL; do
  if [ -n "${!name+x}" ]; then
    envargs+=("$name=${!name}")
  fi
done
while IFS= read -r entry; do
  case "$entry" in
    LC_*=*) envargs+=("$entry") ;;
  esac
done < <(/usr/bin/env)
@EXTRA_ENV@
# Not exec: the EXIT trap has to remove the temp directory after OpenCode returns.
/usr/bin/env -i "${envargs[@]}" /usr/bin/sandbox-exec \
  -D WORKTREE="$worktree" -D TMPDIR="$tmpdir" \
  -f @PROFILE@ @OPENCODE@ "$@"
