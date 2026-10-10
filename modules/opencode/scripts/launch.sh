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

tmpdir="$(realpath "${TMPDIR:-/private/tmp}")"

# Allowlist only. Credentials in the caller's shell never reach OpenCode.
envargs=()
for name in HOME USER LOGNAME PATH TERM COLORTERM LANG TMPDIR SHELL; do
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
exec /usr/bin/env -i "${envargs[@]}" /usr/bin/sandbox-exec \
  -D WORKTREE="$worktree" -D TMPDIR="$tmpdir" \
  -f @PROFILE@ @OPENCODE@ "$@"
