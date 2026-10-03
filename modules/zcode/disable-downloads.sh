# shellcheck shell=bash
substituteInPlace apps/zcode-cli/packages/adapters/src/plugins/zip-source.ts \
  --replace-fail '  const tempRoot = await mkdtemp(join(tmpdir(), ZIP_TEMP_PREFIX));' \
  '  await Promise.reject(new Error("Plugin downloads are disabled in this package"));
  const tempRoot = await mkdtemp(join(tmpdir(), ZIP_TEMP_PREFIX));'
substituteInPlace apps/zcode-cli/packages/adapters/src/plugins/marketplace.ts \
  --replace-fail '  const args = ["clone"];' \
  '  await Promise.reject(new Error("Plugin downloads are disabled in this package"));
  const args = ["clone"];' \
  --replace-fail '  const args = ["clone", "--depth", "1"];' \
  '  await Promise.reject(new Error("Plugin downloads are disabled in this package"));
  const args = ["clone", "--depth", "1"];'
sed -i '/icon: .*OFFICIAL_PLUGIN_ASSETS_BASE_URL/d' \
  apps/zcode-cli/packages/bootstrap/src/app/official-plugin-definitions.ts
