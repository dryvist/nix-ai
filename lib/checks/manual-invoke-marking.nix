# mark-manual-invoke.sh behavioural test.
#
# The tier's whole saving depends on this script marking every marketplace
# skill outside the keep-list. A skill it silently skips stays in every
# session's listing, which is invisible except as a slightly larger number.
#
# The case that motivated this file: the "never double-add" guard grepped the
# WHOLE file, so a skill whose *body* documents `disable-model-invocation:`
# — a skill about authoring skills — matched and was skipped. Two shipped
# skills sat in every session listing that way. Both checks are now scoped to
# the frontmatter block, and the fixture below pins that.
{ pkgs, src }:
{
  manual-invoke-marking = pkgs.runCommand "manual-invoke-marking" { } ''
    mkdir -p src/skills/{body-mentions,already-marked,plain,keepme}

    # Body prose that looks like frontmatter. MUST still be marked.
    cat > src/skills/body-mentions/SKILL.md <<'MD'
    ---
    name: body-mentions
    ---

    Set this in frontmatter:

    disable-model-invocation: true  # for user-only
    MD
    sed -i 's/^    //' src/skills/body-mentions/SKILL.md

    printf -- '---\nname: already-marked\ndisable-model-invocation: true\n---\n\nbody\n' \
      > src/skills/already-marked/SKILL.md
    printf -- '---\nname: plain\n---\n\nbody\n' > src/skills/plain/SKILL.md
    printf -- '---\nname: keepme\n---\n\nbody\n' > src/skills/keepme/SKILL.md

    KEEP_LISTED="keepme" ${pkgs.bash}/bin/bash \
      ${src}/modules/claude/scripts/mark-manual-invoke.sh src out

    # Count the key inside the frontmatter block only.
    count() {
      ${pkgs.gawk}/bin/awk 'NR>1 && /^---$/ { exit }
        NR>1 && /^disable-model-invocation:/ { n++ } END { print n+0 }' "$1"
    }

    fail=0
    check() {
      got=$(count "out/skills/$1/SKILL.md")
      if [ "$got" != "$2" ]; then
        echo "FAIL: $1 expected $2 frontmatter key(s), got $got" >&2
        fail=1
      fi
    }
    # A body mention must not suppress marking.
    check body-mentions 1
    # An already-marked skill must not gain a second key.
    check already-marked 1
    # The ordinary case.
    check plain 1
    # Keep-listed skills stay listed.
    check keepme 0

    [ "$fail" -eq 0 ] || exit 1
    touch $out
  '';
}
