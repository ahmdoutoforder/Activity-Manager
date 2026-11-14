'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('index.html', 'utf8');
const start = html.indexOf('const WORKSPACE_ACTIVITY_FEED_LIMIT = 10;');
const end = html.indexOf('\nasync function readOptionalWorkspaceActivityRows', start);
assert.ok(start >= 0 && end > start, 'workspace activity helpers must exist');

const context = vm.createContext({});
vm.runInContext(
  html.slice(start, end) +
    '\nthis.WORKSPACE_ACTIVITY_FEED_LIMIT = WORKSPACE_ACTIVITY_FEED_LIMIT;' +
    '\nthis.buildWorkspaceActivityItems = buildWorkspaceActivityItems;' +
    '\nthis.isMissingOptionalWorkspaceActivityTable = isMissingOptionalWorkspaceActivityTable;',
  context
);

const build = context.buildWorkspaceActivityItems;
const rows = build({
  tasks: [
    { id: 'task-1', title: 'Lab report', created_by: 'user-a', created_at: '2026-11-14T08:00:00Z', due_date: '2026-11-18' }
  ],
  assignments: [
    { id: 'assignment-1', title: 'PF Assignment 2', created_by: 'user-b', created_at: '2026-11-14T08:30:00Z' }
  ],
  messages: [
    { id: 'message-1', created_by: 'user-c', body: 'I uploaded the slides.', created_at: '2026-11-14T09:00:00Z' }
  ],
  comments: [
    { id: 'comment-1', task_id: 'task-1', created_by: 'user-d', body: 'I can review this.', created_at: '2026-11-14T08:15:00Z' }
  ],
  projects: [
    { id: 'project-1', title: 'Mini project', created_by: 'user-a', created_at: '2026-11-14T07:00:00Z' }
  ],
  notes: [
    { id: 'note-1', title: 'Lecture 4', body: 'Key formulas', created_by: 'user-b', created_at: '2026-11-14T08:45:00Z' }
  ],
  resources: [
    { id: 'resource-1', title: 'Reference link', created_by: 'user-c', created_at: '2026-11-14T06:00:00Z' }
  ],
  assignmentResources: [
    { id: 'file-1', assignment_id: 'assignment-1', uploaded_by: 'user-b', original_file_name: 'brief.pdf', created_at: '2026-11-14T08:40:00Z' }
  ],
  submissions: [
    { id: 'submission-1', assignment_id: 'assignment-1', submitted_by: 'user-d', original_file_name: 'answer.docx', note: 'First version', submitted_at: '2026-11-14T09:15:00Z' }
  ]
});

assert.equal(rows[0].kind, 'submission', 'newest submission should appear first');
assert.equal(rows[0].context, 'submitted work for PF Assignment 2');
assert.equal(rows[1].kind, 'chat');
assert.equal(rows[2].kind, 'note');
assert.equal(rows[3].kind, 'assignment-resource');
assert.equal(rows.find(item => item.kind === 'comment').context, 'commented on Lab report');
assert.equal(rows.find(item => item.kind === 'task').subject, 'Lab report');

const limited = build({
  messages: Array.from({ length: 15 }, (_, index) => ({
    id: String(index), created_by: 'user', body: 'Message ' + index,
    created_at: new Date(Date.UTC(2026, 10, 14, 10, index)).toISOString()
  }))
}, 6);
assert.equal(limited.length, 6, 'the activity feed must respect its requested limit');
assert.equal(limited[0].id, '14', 'activity must be sorted newest first');
const defaultWindow = build({ messages: Array.from({ length: 15 }, (_, index) => ({
  id: String(index), created_by: 'user', body: 'Message ' + index,
  created_at: new Date(Date.UTC(2026, 10, 14, 10, index)).toISOString()
})) });
assert.equal(defaultWindow.length, 10, 'the default event window matches the ten displayed items');
assert.equal(defaultWindow[9].id, '5', 'ten newest items from one busy source must all remain eligible');
assert.equal(
  build({ messages: [{ id: 'bad', created_by: 'user', body: 'Bad date', created_at: 'not-a-date' }] }).length,
  0,
  'events without valid timestamps must be ignored'
);

const feedStart = html.indexOf('async function renderWorkspaceActivity(');
const feedEnd = html.indexOf('\nasync function loadWorkspaceHubMembers', feedStart);
assert.ok(feedStart >= 0 && feedEnd > feedStart, 'activity feed loader must exist');
const feedSource = html.slice(feedStart, feedEnd);
assert.equal(
  (feedSource.match(/\\.limit\\(WORKSPACE_ACTIVITY_FEED_LIMIT\\)/g) || []).length,
  5,
  'each fixed-size event source must query at least the number of rows displayed in the feed'
);
const optionalStart = html.indexOf('async function readOptionalWorkspaceActivityRows(');
const optionalEnd = html.indexOf('\nasync function renderWorkspaceActivity', optionalStart);
assert.ok(optionalStart >= 0 && optionalEnd > optionalStart, 'optional assignment reads must exist');
assert.match(
  html.slice(optionalStart, optionalEnd),
  /\\.limit\\(WORKSPACE_ACTIVITY_FEED_LIMIT\\)/,
  'optional assignment sources must use the same event window'
);

assert.equal(
  context.isMissingOptionalWorkspaceActivityTable({ code: 'PGRST205', message: 'missing table' }),
  true,
  'an unapplied optional assignment migration must not break the base activity feed'
);
assert.equal(
  context.isMissingOptionalWorkspaceActivityTable({ code: '42P01', message: 'relation does not exist' }),
  true
);
assert.equal(
  context.isMissingOptionalWorkspaceActivityTable({ code: '42501', message: 'permission denied' }),
  false,
  'permission problems must not be hidden as missing optional tables'
);

process.stdout.write('Workspace activity feed tests passed.\n');
