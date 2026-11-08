# gsd-core-skills — GSD Core (@opengsd/gsd-core) skill/command files, generated
# at build time for Claude Code and Codex.
#
# Upstream's installer (bin/install.js, exposed as the `gsd-core` bin) is the
# only supported way to produce these files: it rewrites every skill, command
# and agent per runtime. The installer requires no external npm modules — it
# loads only files inside the tarball — so the build runs it directly from the
# pinned npm tarball and fetches nothing beyond that fixed-output source. The
# package's runtime dependencies (@anthropic-ai/claude-agent-sdk, ws) are not
# needed to install and are not part of the emitted trees.
#
# Output layout, relative to each root exactly as the installer generates it:
#
#   claude/                          — a CLAUDE_CONFIG_DIR tree
#     skills/gsd-<name>/SKILL.md     — skills (Claude Code 2.1.88+ discovery)
#     agents/gsd-<name>.md
#     gsd-core/  hooks/  scripts/  .gsd-profile
#
#   codex/                           — a CODEX_HOME tree plus the global skills root
#     agents/gsd-<name>.md + .toml   — Codex agents (native TOML descriptors)
#     .agents/skills/gsd-<name>/SKILL.md — Codex discovers global skills under
#                                          $HOME/.agents, not under $CODEX_HOME
#     gsd-core/  hooks/  scripts/  .gsd-profile
{
  lib,
  stdenv,
  fetchurl,
  nodejs_24,
  version,
}:

stdenv.mkDerivation {
  pname = "gsd-core-skills";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@opengsd/gsd-core/-/gsd-core-${version}.tgz";
    hash = "sha512-3j2ejyDoS4xo0nv9nUwlL8NhgQAEVy4HXsAGdylnEsp2toHTE5AZsDEzZTHv6mpHMtfOyr/vf9ZbdiREyFzvkQ==";
  };

  # npm tarballs unpack to a single `package/` root.
  sourceRoot = "package";

  nativeBuildInputs = [ nodejs_24 ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # HOME inside the build tree: the Codex global install writes its skills
    # root under $HOME/.agents, and the installer's real-home guard expects a
    # HOME that is sandboxed away from the passwd home. GSD_TEST_HOME_SANDBOX
    # is consulted only on hosts where the passwd entry is unreadable.
    export HOME=$NIX_BUILD_TOP/gsd-home
    export GSD_TEST_HOME_SANDBOX=$HOME
    mkdir -p "$HOME"

    node bin/install.js --claude --global --no-legacy-cleanup
    node bin/install.js --codex --global --no-legacy-cleanup

    test -d "$HOME/.agents/skills" || {
      echo "installer produced no $HOME/.agents/skills tree" >&2
      exit 1
    }
    mv "$HOME/.agents" "$out/codex/.agents"

    runHook postInstall
  '';

  meta = {
    description = "GSD Core skills and commands generated for Claude Code and Codex";
    homepage = "https://github.com/open-gsd/gsd-core";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
