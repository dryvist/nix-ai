# shellcheck shell=bash
set -euo pipefail
: "${out:?}"

rm -rf apps/zcode-cli/dependencies
rm apps/zcode-cli/packages/cli/dist/zcode.cjs.map

substituteInPlace pnpm-workspace.yaml \
  --replace-fail '    - darwin' "" \
  --replace-fail '    - linux' "" \
  --replace-fail '    - win32' "" \
  --replace-fail '    - x64' "" \
  --replace-fail '    - arm64' "" \
  --replace-fail '    - glibc' ""

# Workspace packages omit dist via .gitignore; deployment needs built files.
find packages apps/zcode-cli/packages -name package.json \
  -not -path '*/node_modules/*' -execdir touch .npmignore \;

for package in cli node-repl-host browser-use-plugin; do
  pnpm --filter "@zcode/$package" deploy --prod --offline \
    --ignore-scripts --config.node-linker=isolated \
    --config.inject-workspace-packages=true \
    "$out/lib/zcode/apps/zcode-cli/packages/$package"
done

cp -r apps/zcode-cli/packages/bundled-skills "$out/lib/zcode/apps/zcode-cli/packages/"
for plugin in apps/zcode-cli/packages/*-plugin; do
  if [ -d "$plugin/.zcode-plugin" ]; then
    tar -C apps/zcode-cli/packages --exclude=node_modules --exclude='*.map' \
      -cf - "$(basename "$plugin")" |
      tar -C "$out/lib/zcode/apps/zcode-cli/packages" -xf -
  fi
done
