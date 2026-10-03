import { configureCodingPlanApiKey } from "@zcode/bootstrap";
import {
  NodeModelSelectionConfigRepository,
  NodePersonalProviderConfigRepository,
} from "@zcode/provider-node";

const apiKey = process.env.ZAI_API_KEY?.trim();
if (!apiKey) throw new Error("ZAI_API_KEY is required");
async function configure() {
  const configured = await configureCodingPlanApiKey({ apiKey, providerId: "zai", env: process.env });
  const personalRepository = new NodePersonalProviderConfigRepository({
    filePath: configured.configPath,
    pollingIntervalMs: false,
  });
  const repository = new NodeModelSelectionConfigRepository({ personalRepository });
  try {
    const selection = await repository.read();
    if (!selection) throw new Error("Native key initialization produced no model selection");
    await repository.saveConfiguredDefault({ ...selection, modelId: process.env.ZCODE_DEFAULT_MODEL });
  } finally {
    repository.dispose();
    personalRepository.dispose();
  }
}

configure().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
