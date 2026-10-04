import { configureCodingPlanApiKey } from "@zcode/bootstrap";
import {
  NodeModelSelectionConfigRepository,
  createNodeProviderConfigRuntime,
} from "@zcode/provider-node";
import { ProviderConfigMap, ProviderConfigResolver, completeNewModelSelection } from "@zcode/provider";

const apiKey = process.env.ZAI_API_KEY?.trim();
if (!apiKey) throw new Error("ZAI_API_KEY is required");
async function configure() {
  const configured = await configureCodingPlanApiKey({ apiKey, providerId: "zai", env: process.env });
  const runtime = createNodeProviderConfigRuntime({
    zcodeBuiltinFilePath: process.env.ZCODE_BUILTIN_PROVIDER_CONFIG_FILE,
    personalFilePath: configured.configPath,
    personalPollingIntervalMs: false,
    watch: false,
  });
  const repository = new NodeModelSelectionConfigRepository({ personalRepository: runtime.personalRepository });
  try {
    const selection = await repository.read();
    if (!selection) throw new Error("Native key initialization produced no model selection");
    const snapshot = await runtime.configService.read();
    const resolved = new ProviderConfigResolver().resolve({
      ...snapshot,
      accountProviders: new ProviderConfigMap([]),
    });
    const completed = completeNewModelSelection({ providers: resolved.resolvedProviders }, {
      ...selection,
      modelId: process.env.ZCODE_DEFAULT_MODEL,
    });
    if (!completed) throw new Error("Default model is absent from the bundled provider configuration");
    await repository.saveConfiguredDefault(completed);
  } finally {
    repository.dispose();
    runtime.dispose();
  }
}

configure().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
