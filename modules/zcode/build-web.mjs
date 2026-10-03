import { build } from "esbuild";
import {
  resolveBuildAliases,
  resolveBuildExternal,
  createZodDedupePlugin,
  readZodBuildVersion,
} from "./apps/zcode-cli/packages/cli/scripts/build.mjs";

await build({
  entryPoints: ["apps/zcode-cli/packages/cli/configure-key.mjs"],
  outfile: "apps/zcode-cli/packages/cli/dist/configure-key.cjs",
  bundle: true,
  platform: "node",
  format: "cjs",
  metafile: true,
  alias: {
    ...resolveBuildAliases(),
    "@zcode/provider": `${process.cwd()}/packages/provider/src/index.ts`,
  },
  external: resolveBuildExternal(),
  plugins: [createZodDedupePlugin({ expectedV4Version: await readZodBuildVersion() })],
});
await build({
  entryPoints: ["packages/client/src/index.ts"],
  outfile: "packages/web/dist/client.mjs",
  bundle: true,
  platform: "node",
  format: "esm",
});
