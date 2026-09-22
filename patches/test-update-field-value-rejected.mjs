// Unit test: task 3413 defect #5 (corrected) -- `tasks update` called with
// the generic `field`/`value` params (as opposed to `bulk-update`, which
// owns them) was accepted and silently ignored, returning success with
// nothing changed. It must now reject instead of a silent no-op.
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
    async updateTask() {
      throw new Error('test: updateTask must not be called when field/value are rejected');
    },
  },
};

require.cache[require.resolve(`${PKG}/client.js`)] = {
  id: require.resolve(`${PKG}/client.js`),
  filename: require.resolve(`${PKG}/client.js`),
  loaded: true,
  exports: { getVikunjaClient: async () => mockClient },
};

test('update with field/value rejects instead of silently no-op-ing', async () => {
  const { updateTask } = require(`${PKG}/tools/tasks/crud.js`);

  await assert.rejects(
    () => updateTask({ id: 7, field: 'done', value: true }),
    (err) => /field.*value/i.test(err.message),
    'update with field/value must reject with a field/value error, not silently no-op',
  );
});
