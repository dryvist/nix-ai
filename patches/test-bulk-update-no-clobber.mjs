// Unit test: bulkUpdateTasks (task 3413 defect #6) must never trust the
// server's bulk endpoint -- it clobbers every field but the target one to
// its zero value while still reporting success. Prove the per-task
// GET-merge-PUT path is what actually runs, and that untouched fields
// survive.
import { createRequire } from 'module';
import test from 'node:test';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);

const PKG = process.env.VIKUNJA_MCP_DIST || '/tmp/vikunja-patched/dist';

const tasksById = {
  1: { id: 1, title: 't1', description: 'keep me', priority: 3, done: false, project_id: 5 },
  2: { id: 2, title: 't2', description: 'keep me too', priority: 4, done: false, project_id: 5 },
};

const updateCalls = [];
const mockClient = {
  tasks: {
    // The buggy real endpoint: "succeeds" but a faithful mock would clobber
    // other fields. If bulkUpdateTasks ever calls this, the test below
    // proves it by asserting it never sees description/priority survive.
    async bulkUpdateTasks() {
      throw new Error('test: bulkUpdateTasks (server bulk endpoint) must never be called');
    },
    async getTask(id) {
      return tasksById[id];
    },
    async updateTask(id, data) {
      updateCalls.push({ id, data });
      tasksById[id] = data;
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

test('bulk-update field=priority updates only priority; description survives (was clobbered to "")', async () => {
  const { bulkUpdateTasks } = require(`${PKG}/tools/tasks/bulk-operations.js`);

  const result = await bulkUpdateTasks({ taskIds: [1, 2], field: 'priority', value: 5 });
  const parsed = JSON.parse(result.content[0].text);

  assert.equal(updateCalls.length, 2, 'expected 2 per-task updateTask calls');
  for (const { id, data } of updateCalls) {
    assert.equal(data.priority, 5, `task ${id} priority not updated`);
    assert.equal(
      data.description,
      id === 1 ? 'keep me' : 'keep me too',
      `task ${id} description was clobbered`,
    );
  }
  assert.ok(parsed.success, 'bulkUpdateTasks reported failure');
});
