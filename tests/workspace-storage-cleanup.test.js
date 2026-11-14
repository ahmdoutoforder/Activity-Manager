const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('index.html', 'utf8');
const start = html.indexOf('async function drainWorkspaceStorageCleanupJobs()');
const endMarker = '\n}\n\n/* Resume queued cleanup after sign-in';
const end = html.indexOf(endMarker, start);
assert.ok(start >= 0 && end > start, 'cleanup worker source must be present in index.html');
const workerSource = html.slice(start, end + 2);
const bucketName = 'uniplanner-workspace-files';
const workspaceId = '11111111-1111-4111-8111-111111111111';
const memberId = '22222222-2222-4222-8222-222222222222';

function createWorker({ removeFails = false, listFails = false, invalidPath = false, missingQueue = false, jobCount = 1 } = {}) {
  const deletedJobs = new Set();
  const jobs = Array.from({ length: jobCount }, (_, i) => ({
    id: 'cleanup-job-' + (i + 1),
    workspace_id: i === 0
      ? workspaceId
      : '11111111-1111-4111-8111-' + String(i + 1).padStart(12, '0')
  }));
  const rangeCalls = [];
  const removeCalls = [];
  const listCalls = [];
  const resourceFiles = Array.from({ length: 1001 }, (_, i) => ({
    name: 'resource-' + String(i).padStart(4, '0') + '.pdf',
    id: 'resource-object-' + i
  }));

  const bucket = {
    async list(prefix, options = {}) {
      listCalls.push({ prefix, limit: options.limit, offset: options.offset || 0 });
      if (listFails) return { data: null, error: { message: 'simulated Storage listing failure' } };
      if (prefix === workspaceId) {
        return { data: [{ name: 'assignment-1', id: null }], error: null };
      }
      if (prefix.startsWith('11111111-1111-4111-8111-') && prefix !== workspaceId) {
        return { data: [], error: null };
      }
      if (prefix === workspaceId + '/assignment-1') {
        return {
          data: [
            { name: 'resources', id: null },
            { name: 'submissions', id: null },
            ...(invalidPath ? [{ name: 'other', id: null }] : [])
          ],
          error: null
        };
      }
      if (prefix === workspaceId + '/assignment-1/resources') {
        const offset = options.offset || 0;
        return { data: resourceFiles.slice(offset, offset + options.limit), error: null };
      }
      if (prefix === workspaceId + '/assignment-1/submissions') {
        return { data: [{ name: memberId, id: null }], error: null };
      }
      if (prefix === workspaceId + '/assignment-1/submissions/' + memberId) {
        return { data: [{ name: 'submission.docx', id: 'submission-object' }], error: null };
      }
      if (prefix === workspaceId + '/assignment-1/other') {
        return { data: [{ name: 'unrecognized.bin', id: 'other-object' }], error: null };
      }
      throw new Error('Unexpected list prefix: ' + prefix);
    },
    async remove(paths) {
      removeCalls.push(paths.slice());
      if (removeFails) return { data: null, error: { message: 'simulated Storage deletion failure' } };
      return { data: paths.map(path => ({ name: path })), error: null };
    }
  };

  const db = {
    from(table) {
      assert.equal(table, 'uniplanner_workspace_storage_cleanup_jobs');
      return {
        select() { return this; },
        order() { return this; },
        async range(from, to) {
          rangeCalls.push({ from, to });
          if (missingQueue) {
            return { data: null, error: { code: 'PGRST205', message: 'Could not find the table in the schema cache' } };
          }
          return { data: jobs.slice(from, to + 1), error: null };
        },
        delete() {
          return {
            eq(column, value) {
              assert.equal(column, 'id');
              const job = jobs.find(item => item.id === value);
              return {
                async select() {
                  if (job) deletedJobs.add(value);
                  return { data: job ? [{ id: value }] : [], error: null };
                }
              };
            }
          };
        }
      };
    },
    storage: { from(name) { assert.equal(name, bucketName); return bucket; } }
  };

  const context = vm.createContext({
    supa: db,
    user: { id: memberId },
    console: { info() {}, warn() {} }
  });
  vm.runInContext(
    "const ASSIGNMENT_FILE_BUCKET = '" + bucketName + "';\n" +
    'let workspaceStorageCleanupPromise = null;\n' +
    workerSource + '\nthis.runWorker = drainWorkspaceStorageCleanupJobs;',
    context
  );

  return {
    run: () => context.runWorker(),
    removeCalls,
    listCalls,
    rangeCalls,
    get deletedJobCount() { return deletedJobs.size; }
  };
}

(async () => {
  {
    const fixture = createWorker();
    const result = await fixture.run();
    assert.equal(result.completed, 1);
    assert.equal(result.failed, 0);
    assert.equal(result.removed, 1002);
    assert.deepEqual(fixture.removeCalls.map(batch => batch.length), [1000, 2]);
    assert.ok(fixture.listCalls.some(call => call.offset === 1000), 'worker must paginate Storage listings');
    assert.equal(fixture.deletedJobCount, 1, 'job is deleted only after all removals succeed');
  }

  {
    const fixture = createWorker({ jobCount: 12 });
    const result = await fixture.run();
    assert.equal(result.completed, 12, 'the worker must drain beyond the first ten jobs');
    assert.equal(result.failed, 0);
    assert.equal(result.total, 12);
    assert.equal(fixture.deletedJobCount, 12);
    assert.deepEqual(fixture.rangeCalls.map(range => range.from), [0], '12 jobs fit in one 100-row page');
  }

  {
    const fixture = createWorker({ removeFails: true });
    const result = await fixture.run();
    assert.equal(result.completed, 0);
    assert.equal(result.failed, 1);
    assert.equal(fixture.deletedJobCount, 0, 'failed deletion must leave its job queued');
  }

  {
    const fixture = createWorker({ listFails: true });
    const result = await fixture.run();
    assert.equal(result.completed, 0);
    assert.equal(result.failed, 1);
    assert.equal(fixture.removeCalls.length, 0, 'listing failure must prevent all removals');
    assert.equal(fixture.deletedJobCount, 0, 'listing failure must leave its job queued');
  }

  {
    const fixture = createWorker({ invalidPath: true });
    const result = await fixture.run();
    assert.equal(result.completed, 0);
    assert.equal(result.failed, 1);
    assert.equal(fixture.removeCalls.length, 0, 'unknown object paths must never be deleted');
    assert.equal(fixture.deletedJobCount, 0);
  }

  {
    const fixture = createWorker({ missingQueue: true });
    const result = await fixture.run();
    assert.equal(result.skipped, true, 'production without the pending migration must remain usable');
  }

  process.stdout.write('Workspace Storage cleanup worker tests passed.\n');
})().catch(error => {
  process.stderr.write(String(error.stack || error) + '\n');
  process.exitCode = 1;
});
