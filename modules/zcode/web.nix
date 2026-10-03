{
  lib,
  zcode,
  nodejs_24,
  ripgrep,
  bfs,
  ugrep,
}:

zcode.overrideAttrs (old: {
  pname = "zcode-web";
  inherit (zcode) src pnpmDeps;
  buildPhase =
    (lib.replaceStrings [ "pnpm --filter" ] [ "pnpm --reporter=append-only --filter" ] old.buildPhase)
    + ''
        export ZCODE_ENV=production
      pnpm --filter @zcode/server exec tsup
      pnpm --filter @zcode/web run build
      cp ${./configure-key.mjs} apps/zcode-cli/packages/cli/configure-key.mjs
      cp ${./build-web.mjs} nix-build-web.mjs
      node nix-build-web.mjs
    '';
  installPhase = old.installPhase + ''
    pnpm --filter @zcode/server deploy --prod --offline \
      --ignore-scripts --config.node-linker=isolated \
      --config.inject-workspace-packages=true "$out/lib/zcode/packages/server"
    mkdir -p "$out/share/zcode-web"
    cp -r packages/web/dist/. "$out/share/zcode-web/"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/zcode-configure-key" \
      --add-flags "$out/lib/zcode/apps/zcode-cli/packages/cli/dist/configure-key.cjs" \
      --set ZCODE_DEFAULT_MODEL ${(import ../../vars/ai-stack.nix).zai.zcode.model} \
      --set ZCODE_BUILTIN_PROVIDER_CONFIG_FILE "$out/lib/zcode/apps/zcode-cli/packages/cli/dist/provider/zcode-builtin.json" \
      --set ZCODE_ENV production
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/zcode-web" \
      --add-flags "$out/lib/zcode/packages/server/dist/entry-http.js" \
      --run ': "''${ZCODE_SERVER_AUTH_TOKEN:?ZCODE_SERVER_AUTH_TOKEN is required}"' \
      --set ZCODE_ENV production \
      --set NODE_USE_ENV_PROXY 1 \
      --prefix PATH : ${
        lib.makeBinPath [
          ripgrep
          bfs
          ugrep
        ]
      } \
      --set-default ZCODE_SERVER_HOST 127.0.0.1 \
      --set ZCODE_WEB_STATIC_ROOT "$out/share/zcode-web" \
      --set ZCODE_AGENT_SERVER_COMMAND "$out/bin/zcode"
  '';
  meta = old.meta // {
    description = "Z.ai coding agent native Web UI and HTTP server";
    mainProgram = "zcode-web";
  };
})
