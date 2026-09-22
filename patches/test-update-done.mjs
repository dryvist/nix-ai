// Regression check: `update` with the typed `done: true` parameter already
// worked (confirmed live) -- task 3413 defect #5 turned out to be
// `field`/`value` on `update`, not this path (see
// test-update-field-value-rejected.mjs). Kept as a guard against
// regressing the working path while that fix touched the same function.
import { createRequire } from 'module';
import test from 'node:test';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);

const PKG = process.env.VIKUNJA_MCP_DIST || '/tmp/vikunja-patched/dist';

const mockClient = {
  tasks: {
    async getTask(id) {
      return { id, title: 'existing', project_id: 1, done: false };
    },
    async updateTask(id, data) {
      mockClient.tasks._lastUpdate = data;
      return data;
    },
  },
};

require.cache[require.resolve(`${PKG}/client.js`)] = {
  id: require.resolve(`${PKG}/client.js`),
  filename: require.resolve(`${PKG}/client.js`),
  loaded: true,
  exports: { getVikunjaClient: async () => mockClient },
};

test('update done=true (typed param) still sends done:true and reports "done" as affected', async () => {
  const { updateTask } = require(`${PKG}/tools/tasks/crud.js`);
  mockClient.tasks._lastUpdate = null;
  const result = await updateTask({ id: 7, done: true });
  const parsed = JSON.parse(result.content[0].text);

  assert.equal(mockClient.tasks._lastUpdate?.done, true, 'updateTask did not send done: true to the API');
  assert.ok(parsed.metadata.affectedFields.includes('done'), 'response affectedFields missing "done"');
});
