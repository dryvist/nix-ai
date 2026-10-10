# Launches OpenCode under the Seatbelt profile. sandbox.nix fills the placeholders.

refuse() {
  echo "opencode: refusing to run with $1 as the worktree; cd into a project first" >&2
  exit 1
}

home_dir=@HOME@

# The worktree is the git toplevel of the cwd, else the cwd itself.
worktree="$(realpath "$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)")"
case "$worktree" in
  / | "$home_dir") refuse "$worktree" ;;
esac
# A worktree above the home directory would make the home directory writable.
case "$home_dir/" in
  "$worktree/"*) refuse "$worktree" ;;
esac

common="$(realpath "$(git rev-parse --git-common-dir 2>/dev/null || echo "$worktree")")"
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
  -D WORKTREE="$worktree" -D GIT_COMMON="$common" -D TMPDIR="$tmpdir" \
  -f @PROFILE@ @OPENCODE@ "$@"
