# herdr-hail — the Slack/Discord bridge for herdr.
#
# Upstream (natori-hrj/herdr-hail) ships this as a herdr PLUGIN: a
# `herdr-plugin.toml` manifest declaring one `[[panes]]` entrypoint, installed
# with `herdr plugin install` and opened with `herdr plugin pane open
# hail/bridge`. That is an interactive workflow — the manifest declares no
# `[[startup]]` hook, so registering the plugin does NOT make the bridge run.
#
# The guest wants it running unattended, so modules/herdr/nixos.nix runs
# dist/index.js as its own unit rather than going through the plugin host. The
# bridge needs exactly two things from herdr, and both are plain environment
# variables a unit can set itself:
#
#   HERDR_SOCKET_PATH        the control socket        (src/herdr.ts)
#   HERDR_PLUGIN_CONFIG_DIR  directory of config.json  (src/config.ts)
#
# Nothing else the plugin host provides is load-bearing here, which is why this
# is a package plus a unit instead of a plugin registration.
{
  lib,
  buildNpmPackage,
  nodejs,
  makeWrapper,
  src,
}:

buildNpmPackage {
  pname = "herdr-hail";
  # package.json says 0.1.0 and upstream cuts no tags, so the date of the
  # pinned rev is the only thing that distinguishes two builds of it.
  version = "0.1.0-unstable-2026-07-19";
  inherit src;

  # `prefetch-npm-deps package-lock.json` at the pinned rev. Moves only when
  # the lockfile does, which is the reason the input is pinned by rev.
  npmDepsHash = "sha256-DTS0Wcfq32/1kV3E/jMvEHOrkcfeavUQZaGeSzfXWZg=";

  nativeBuildInputs = [ makeWrapper ];

  # `npm run build` is bare `tsc` — the same command the manifest's [[build]]
  # block runs when herdr installs from GitHub. Running it here is what makes
  # the plugin host unnecessary at runtime.

  # npm's own install would link dist/index.js as `bin/herdr-hail`, but tsc
  # emits it without a shebang or the executable bit, so the link is unusable.
  # Install by hand and wrap instead.
  dontNpmInstall = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/herdr-hail
    cp -r dist node_modules package.json $out/lib/herdr-hail/
    # Not used by the unit, but shipping it keeps
    # `herdr plugin link <out>/lib/herdr-hail` working for anyone who does
    # want the interactive pane.
    cp herdr-plugin.toml $out/lib/herdr-hail/

    makeWrapper ${lib.getExe nodejs} $out/bin/herdr-hail \
      --add-flags $out/lib/herdr-hail/dist/index.js

    runHook postInstall
  '';

  passthru = {
    # Path suffix to hand `herdr plugin link`, for the interactive pane route.
    pluginSubdir = "lib/herdr-hail";
  };

  meta = {
    description = "Two-way Slack and Discord bridge for the herdr agent multiplexer";
    homepage = "https://github.com/natori-hrj/herdr-hail";
    license = lib.licenses.asl20;
    mainProgram = "herdr-hail";
    platforms = lib.platforms.unix;
  };
}
