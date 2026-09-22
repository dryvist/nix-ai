// Unit test: bulkUpdateTasks (task 3413 defect #6) must never trust the
// server's bulk endpoint -- it clobbers every field but the target one to
// its zero value while still reporting success. Prove the per-task
// GET-merge-PUT path is what actually runs, and that untouched fields
// survive.
import { createRequire } from 'module';
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

let failed = false;
const { bulkUpdateTasks } = require(`${PKG}/tools/tasks/bulk-operations.js`);

const result = await bulkUpdateTasks({ taskIds: [1, 2], field: 'priority', value: 5 });
const parsed = JSON.parse(result.content[0].text);

if (updateCalls.length !== 2) {
  console.error('FAIL: expected 2 per-task updateTask calls, got', updateCalls.length);
  failed = true;
}
for (const { id, data } of updateCalls) {
  if (data.priority !== 5) {
    console.error(`FAIL: task ${id} priority not updated, got`, data.priority);
    failed = true;
  }
  if (data.description !== (id === 1 ? 'keep me' : 'keep me too')) {
    console.error(`FAIL: task ${id} description was clobbered, got`, JSON.stringify(data.description));
    failed = true;
  }
}
if (!parsed.success) {
  console.error('FAIL: bulkUpdateTasks reported failure', parsed);
  failed = true;
}

if (!failed) {
  console.log('PASS: bulk-update field=priority updates only priority; description survives (was clobbered to "")');
}

process.exit(failed ? 1 : 0);
