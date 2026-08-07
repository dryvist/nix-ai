#!/usr/bin/env bash
# Push AI session history to per-vendor S3 buckets (RustFS).
# Called by the launchd agent in modules/session-archive.nix.
#
# Arguments: <aws-bin> <log-dir> <lock-dir> <endpoint>
# then a "--vendors" list of dir=bucket pairs, then an "--excludes" list.
set -uo pipefail

aws_bin="$1"
log_dir="$2"
lock_dir="$3"
endpoint="$4"
shift 4

vendors=()
excludes=()
mode=""
for arg in "$@"; do
  case "$arg" in
    --vendors) mode="vendors" ;;
    --excludes) mode="excludes" ;;
    *) [ "$mode" = "vendors" ] && vendors+=("$arg") || excludes+=("$arg") ;;
  esac
done

mkdir -p "$log_dir"
log="$log_dir/archive.log"

# mkdir is atomic, so it doubles as the lock. A stale lock older than 12h is
# assumed dead — never reclaiming would silently stop archiving forever.
if ! mkdir "$lock_dir" 2>/dev/null; then
  if [ -n "$(find "$lock_dir" -maxdepth 0 -mmin +720 2>/dev/null)" ]; then
    echo "$(date -Iseconds) reclaiming stale lock" >>"$log"
    rmdir "$lock_dir" 2>/dev/null || true
    mkdir "$lock_dir" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

# Fail loudly on missing auth: a helper that exits 0 having archived nothing is
# the known estate bug — silence here reads as "backed up" while nothing was.
for v in VAULT_ADDR AI_SESSIONS_BACKUP_ROLE_ID AI_SESSIONS_BACKUP_SECRET_ID; do
  if [ -z "${!v:-}" ]; then
    echo "$(date -Iseconds) missing $v — doppler injection absent" >>"$log"
    exit 1
  fi
done

token=$(curl -sf -X POST "$VAULT_ADDR/v1/auth/approle/login" \
  -d "{\"role_id\":\"$AI_SESSIONS_BACKUP_ROLE_ID\",\"secret_id\":\"$AI_SESSIONS_BACKUP_SECRET_ID\"}" |
  python3 -c 'import sys,json; print(json.load(sys.stdin)["auth"]["client_token"])' 2>/dev/null)
if [ -z "$token" ]; then
  echo "$(date -Iseconds) approle login failed" >>"$log"
  exit 1
fi

secrets=$(curl -sf -H "X-Vault-Token: $token" \
  "$VAULT_ADDR/v1/secret/data/apps/ai-sessions")
if [ -z "$secrets" ]; then
  echo "$(date -Iseconds) secret read failed" >>"$log"
  exit 1
fi

exclude_args=()
for e in "${excludes[@]}"; do exclude_args+=(--exclude "$e"); done

# aws exits 2 when it skipped sockets/specials but transferred everything else;
# that is routine inside these trees, so 2 counts as success. 1 or >2 is real.
run_aws() {
  local rc=0
  "$aws_bin" --endpoint-url "$endpoint" "$@" >>"$log" 2>&1 || rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 2 ]
}

started=$(date +%s)
dirs=0
failed=0
for pair in "${vendors[@]}"; do
  rel="${pair%%=*}"
  bkt="${pair#*=}"
  src="$HOME/$rel"
  [ -d "$src" ] || continue
  # Key derivation: bucket ai-sessions-claude -> claude_rw_secret.
  key="${bkt#ai-sessions-}_rw_secret"
  secret=$(printf '%s' "$secrets" | python3 -c \
    'import sys,json; print(json.load(sys.stdin)["data"]["data"][sys.argv[1]])' \
    "$key" 2>/dev/null)
  if [ -z "$secret" ]; then
    echo "$(date -Iseconds) no secret $key for $bkt, skipping $rel" >>"$log"
    failed=$((failed + 1))
    continue
  fi
  export AWS_ACCESS_KEY_ID="$bkt-rw" AWS_SECRET_ACCESS_KEY="$secret"

  # Per-leaf sync, never whole-tree: the store's ListObjectsV2 truncates on
  # large parent prefixes, so a whole-tree sync fails to see what is already
  # uploaded and re-pushes tens of thousands of present objects every run
  # (verified live). Depth-1 subdirectory prefixes stay small enough to list.
  while IFS= read -r sub; do
    dirs=$((dirs + 1))
    if ! run_aws s3 sync "$sub/" "s3://$bkt/$rel/${sub##*/}/" \
      --no-follow-symlinks --only-show-errors "${exclude_args[@]}"; then
      echo "$(date -Iseconds) sync $rel/${sub##*/} failed" >>"$log"
      failed=$((failed + 1))
    fi
  done < <(find "$src" -maxdepth 1 -mindepth 1 -type d)

  # Root-level files are few and small: cp unconditionally, bucket versioning
  # absorbs the re-uploads. Reuse the exclude patterns so credentials at the
  # top level never leave the machine.
  while IFS= read -r f; do
    skip=0
    for e in "${excludes[@]}"; do
      # shellcheck disable=SC2254  # $e is a glob pattern by contract
      case "${f##*/}" in $e) skip=1 ;; esac
    done
    [ "$skip" = 1 ] && continue
    if ! run_aws s3 cp "$f" "s3://$bkt/$rel/${f##*/}" --only-show-errors; then
      echo "$(date -Iseconds) cp $rel/${f##*/} failed" >>"$log"
      failed=$((failed + 1))
    fi
  done < <(find "$src" -maxdepth 1 -type f)
done

echo "$(date -Iseconds) archive finished dirs=$dirs failed=$failed in $(($(date +%s) - started))s" >>"$log"
[ "$failed" = 0 ]
