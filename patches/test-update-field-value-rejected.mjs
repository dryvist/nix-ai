// Unit test: task 3413 defect #5 (corrected) -- `tasks update` called with
// the generic `field`/`value` params (as opposed to `bulk-update`, which
// owns them) was accepted and silently ignored, returning success with
// nothing changed. It must now reject instead of a silent no-op.
import { createRequire } from 'module';
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

let failed = false;
const { updateTask } = require(`${PKG}/tools/tasks/crud.js`);

try {
  await updateTask({ id: 7, field: 'done', value: true });
  console.error('FAIL: update with field/value returned success instead of rejecting');
  failed = true;
} catch (err) {
  if (!/field.*value/i.test(err.message)) {
    console.error('FAIL: rejected for the wrong reason:', err.message);
    failed = true;
  } else {
    console.log('PASS: update with field/value rejects instead of silently no-op-ing:', err.message);
  }
}

process.exit(failed ? 1 : 0);
