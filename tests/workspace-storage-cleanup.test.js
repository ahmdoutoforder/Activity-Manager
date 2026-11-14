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

function createWorker({ removeFails = false, listFails = false, invalidPath = false, missingQueue = false } = {}) {
  let jobDeleted = false;
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
        async limit() {
          if (missingQueue) {
            return { data: null, error: { code: 'PGRST205', message: 'Could not find the table in the schema cache' } };
          }
          return {
            data: jobDeleted ? [] : [{ id: 'cleanup-job-1', workspace_id: workspaceId }],
            error: null
          };
        },
        delete() {
          return {
            eq(column, value) {
              assert.equal(column, 'id');
              assert.equal(value, 'cleanup-job-1');
              return {
                async select() {
                  jobDeleted = true;
                  return { data: [{ id: 'cleanup-job-1' }], error: null };
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
    get jobDeleted() { return jobDeleted; }
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
    assert.equal(fixture.jobDeleted, true, 'job is deleted only after all removals succeed');
  }

  {
    const fixture = createWorker({ removeFails: true });
    const result = await fixture.run();
    assert.equal(result.completed, 0);
    assert.equal(result.failed, 1);
    assert.equal(fixture.jobDeleted, false, 'failed deletion must leave its job queued');
  }

  {
    const fixture = createWorker({ listFails: true });
    const result = await fixture.run();
    assert.equal(result.completed, 0);
    assert.equal(result.failed, 1);
    assert.equal(fixture.removeCalls.length, 0, 'listing failure must prevent all removals');
    assert.equal(fixture.jobDeleted, false, 'listing failure must leave its job queued');
  }

  {
    const fixture = createWorker({ invalidPath: true });
    const result = await fixture.run();
    assert.equal(result.completed, 0);
    assert.equal(result.failed, 1);
    assert.equal(fixture.removeCalls.length, 0, 'unknown object paths must never be deleted');
    assert.equal(fixture.jobDeleted, false);
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
