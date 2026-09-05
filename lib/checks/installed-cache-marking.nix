# mark-installed-cache.sh behavioural test.
#
# This script closes the gap the marketplace derivation cannot reach: index
# marketplaces whose plugin content Claude fetches itself, so nix never sees a
# SKILL.md to mark. It writes into a tree Claude also writes to, which makes
# three properties non-negotiable and pinned here: it never marks a keep-listed
# skill, it never writes through a store symlink, and re-running marks nothing.
{ pkgs, src }:
{
  installed-cache-marking = pkgs.runCommand "installed-cache-marking" { } ''
    mkdir -p cache/mkt/plug/1.0.0/skills/{body-mentions,already-marked,plain,keepme}
    root=$PWD/cache

    cat > $root/mkt/plug/1.0.0/skills/body-mentions/SKILL.md <<'MD'
    ---
    name: body-mentions
    ---

    disable-model-invocation: true  # documented in prose, not frontmatter
    MD
    sed -i 's/^    //' $root/mkt/plug/1.0.0/skills/body-mentions/SKILL.md

    printf -- '---\nname: already-marked\ndisable-model-invocation: true\n---\n\nb\n' \
      > $root/mkt/plug/1.0.0/skills/already-marked/SKILL.md
    printf -- '---\nname: plain\n---\n\nb\n' > $root/mkt/plug/1.0.0/skills/plain/SKILL.md
    printf -- '---\nname: keepme\n---\n\nb\n' > $root/mkt/plug/1.0.0/skills/keepme/SKILL.md

    # A skill marked on disk and LATER promoted into the keep-list must be
    # unmarked again. Without this the promotion applies in config and does
    # nothing on disk, and which behaviour you get depends on run order.
    mkdir -p $root/mkt/plug/1.0.0/skills/promoted
    printf -- '---\nname: promoted\ndisable-model-invocation: true\n---\n\nb\n' \
      > $root/mkt/plug/1.0.0/skills/promoted/SKILL.md

    # A store-style symlink must never be written through.
    mkdir -p store/skills/fromstore
    printf -- '---\nname: fromstore\n---\n\nb\n' > store/skills/fromstore/SKILL.md
    chmod -w store/skills/fromstore/SKILL.md
    mkdir -p $root/mkt/plug/1.0.0/skills/fromstore
    ln -s $PWD/store/skills/fromstore/SKILL.md \
      $root/mkt/plug/1.0.0/skills/fromstore/SKILL.md

    run() {
      KEEP_LISTED="keepme promoted" ${pkgs.bash}/bin/bash \
        ${src}/modules/claude/scripts/mark-installed-cache.sh "$root" 2>&1
    }
    first=$(run)
    second=$(run)

    count() {
      ${pkgs.gawk}/bin/awk 'NR>1 && /^---$/ { exit }
        NR>1 && /^disable-model-invocation:/ { n++ } END { print n+0 }' "$1"
    }

    fail=0
    check() {
      got=$(count "$root/mkt/plug/1.0.0/skills/$1/SKILL.md")
      [ "$got" = "$2" ] || { echo "FAIL: $1 want $2 got $got" >&2; fail=1; }
    }
    check body-mentions 1     # body prose must not suppress marking
    check already-marked 1    # no double-add
    check plain 1             # ordinary case
    check keepme 0            # keep-listed stays listed
    check promoted 0          # promoted into the keep-list: unmarked again

    # The symlink target must be untouched.
    if ${pkgs.gnugrep}/bin/grep -q disable-model-invocation \
        store/skills/fromstore/SKILL.md; then
      echo "FAIL: wrote through a store symlink" >&2; fail=1
    fi

    # Idempotent: the second run marks nothing.
    case "$second" in
      *"marked=0"*) ;;
      *) echo "FAIL: not idempotent: $second" >&2; fail=1 ;;
    esac

    [ "$fail" -eq 0 ] || exit 1
    touch $out
  '';
}
