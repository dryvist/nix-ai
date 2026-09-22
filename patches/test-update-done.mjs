import { createRequire } from 'module';
const require = createRequire(import.meta.url);

// Point at wherever the patched package actually lands in the real build.
const PKG = process.env.VIKUNJA_MCP_DIST || '/tmp/vikunja-patched/dist';

const mockClient = {
  tasks: {
    async getTask(id) {
      // currentTask.done starts false, matching the live repro (tasks 3407/3411).
      return { id, title: 'existing', project_id: 1, done: false, done_at: null };
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

let failed = false;

// --- Defect 5: update done=true must set done + affectedFields, not silently no-op ---
const { updateTask } = require(`${PKG}/tools/tasks/crud.js`);
mockClient.tasks._lastUpdate = null;
const result = await updateTask({ id: 7, done: true });
const parsed = JSON.parse(result.content[0].text);

if (mockClient.tasks._lastUpdate?.done !== true) {
  console.error('FAIL: updateTask did not send done: true to the API, got', mockClient.tasks._lastUpdate);
  failed = true;
} else if (!mockClient.tasks._lastUpdate?.done_at) {
  console.error('FAIL: updateTask sent done: true without done_at');
  failed = true;
} else if (!parsed.metadata.affectedFields.includes('done')) {
  console.error('FAIL: response affectedFields missing "done", got', parsed.metadata.affectedFields);
  failed = true;
} else {
  console.log('PASS: update done=true sends done:true + done_at and reports "done" as affected (was a silent no-op)');
}

process.exit(failed ? 1 : 0);
