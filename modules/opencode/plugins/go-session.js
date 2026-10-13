export const OpenCodeGoSession = async () => ({
  "chat.headers": async ({ sessionID, model }, output) => {
    const routerGo =
      model.providerID === "litellm" && model.modelID.startsWith("go-");
    const directGo =
      model.providerID === "opencode-go" ||
      model.providerID === "opencode-go-anthropic";

    if (routerGo || directGo) {
      output.headers["x-opencode-session"] = sessionID;
    }
  },
});
