// Search-before-create: `create` and `bulk-create` comment on an open task
// whose normalized title matches, instead of creating a duplicate.
import { createRequire } from 'module';
import test from 'node:test';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);

const PKG = process.env.VIKUNJA_MCP_DIST || '/tmp/vikunja-patched/dist';

const store = [];
const comments = [];
const mockClient = {
  tasks: {
    async getProjectTasks(projectId, params) {
      return store.filter((t) => t.project_id === projectId && t.title.toLowerCase().includes(params.s.toLowerCase()));
    },
    async createTask(projectId, data) {
      const task = { id: 100 + store.length, done: false, ...data, project_id: projectId };
      store.push(task);
      return task;
    },
    async getTask(id) {
      return store.find((t) => t.id === id);
    },
    async createTaskComment(id, data) {
      comments.push({ id, ...data });
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

const { createTask } = require(`${PKG}/tools/tasks/crud.js`);
const parse = (result) => JSON.parse(result.content[0].text);

test('second create with the same title comments on the open task', async () => {
  const first = parse(await createTask({ projectId: 5, title: 'Fix the thing' }));
  const second = parse(await createTask({ projectId: 5, title: 'Fix the thing', description: 'new evidence' }));
  assert.equal(second.deduplicated, true);
  assert.equal(second.task.id, first.task.id);
  assert.equal(store.length, 1);
  assert.equal(comments.at(-1).id, first.task.id);
  assert.match(comments.at(-1).comment, /new evidence/);
});

test('negative: different title, other project, or done task still creates', async () => {
  await createTask({ projectId: 5, title: 'Fix the thing, part two' });
  await createTask({ projectId: 6, title: 'Fix the thing' });
  store[0].done = true;
  await createTask({ projectId: 5, title: 'Fix the thing' });
  assert.equal(store.length, 4);
});

test('bulk-create dedupes against open tasks and within the batch', async () => {
  const { bulkCreateTasks } = require(`${PKG}/tools/tasks/bulk-operations.js`);
  const before = store.length;
  await bulkCreateTasks({ projectId: 7, tasks: [{ title: 'Same' }, { title: 'same!' }] });
  assert.equal(store.length, before + 1);
});
