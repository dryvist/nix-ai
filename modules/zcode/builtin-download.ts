import type { ZCodeBuiltinRelease } from "./zcode-builtin-release.js";

export interface ZCodeBuiltinDownloadOptions {
  readonly endpointOrigin: string;
  readonly appVersion: string;
  readonly platform: string;
  readonly request: (url: string | URL, init: RequestInit) => Promise<Response>;
  readonly signal?: AbortSignal;
}

export async function downloadZCodeBuiltinRelease(
  _options: ZCodeBuiltinDownloadOptions,
): Promise<ZCodeBuiltinRelease | null> {
  return null;
}
