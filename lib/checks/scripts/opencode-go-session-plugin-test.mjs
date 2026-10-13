import assert from "node:assert/strict";

const { OpenCodeGoSession } = await import("file://" + process.argv[2]);
const hooks = await OpenCodeGoSession();

for (const [providerID, modelID] of [
  ["litellm", "go-mimo-flash"],
  ["opencode-go", "mimo-v2.6-flash"],
  ["opencode-go-anthropic", "qwen3.7-plus"],
]) {
  const output = { headers: { "x-test": "kept" } };
  await hooks["chat.headers"](
    {
      sessionID: "ses_0123456789ababcdefghijklmn",
      model: { providerID, modelID },
    },
    output,
  );
  assert.equal(output.headers["x-opencode-session"], "ses_0123456789ababcdefghijklmn");
  assert.equal(output.headers["x-test"], "kept");
}

const output = { headers: {} };
await hooks["chat.headers"](
  {
    sessionID: "ses_0123456789ababcdefghijklmn",
    model: { providerID: "litellm", modelID: "medium" },
  },
  output,
);
assert.equal(output.headers["x-opencode-session"], undefined);
