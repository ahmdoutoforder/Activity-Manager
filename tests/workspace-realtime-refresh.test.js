'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('index.html', 'utf8');
const start = html.indexOf('function handleWorkspaceCollaborationRealtime(');
const end = html.indexOf('\n\nlet groupNotificationChannel', start);
assert.ok(start >= 0 && end > start, 'Realtime activity handler must exist');

const calls = { refreshes: [], notifications: [] };
const context = vm.createContext({
  user: { id: 'self' },
  prefs: { groupNotifications: false },
  window: { Notification: {} },
  Notification: { permission: 'default' },
  queueWorkspaceActivityRefresh: workspaceId => calls.refreshes.push(workspaceId),
  sendPlannerNotification: (...args) => { calls.notifications.push(args); return Promise.resolve(); },
  Date
});
vm.runInContext(
  html.slice(start, end) + '\nthis.handleWorkspaceCollaborationRealtime = handleWorkspaceCollaborationRealtime;',
  context
);

const handle = context.handleWorkspaceCollaborationRealtime;
handle({ new: { id: 'message-1', workspace_id: 'workspace-1', created_by: 'classmate' } }, 'message');
assert.deepEqual(calls.refreshes, ['workspace-1'], 'foreground feed refresh must not depend on notification preference');
assert.equal(calls.notifications.length, 0, 'notifications remain disabled when the preference is off');

context.prefs.groupNotifications = true;
context.Notification.permission = 'granted';
handle({ new: { id: 'comment-1', workspace_id: 'workspace-1', created_by: 'classmate' } }, 'comment');
assert.equal(calls.refreshes.length, 2);
assert.equal(calls.notifications.length, 1, 'a permitted classmate event still creates a notification');
assert.equal(calls.notifications[0][0], 'group:comment:comment-1');

handle({ new: { id: 'own-task', workspace_id: 'workspace-1', created_by: 'self' } }, 'task');
assert.equal(calls.refreshes.length, 3, 'the feed refreshes for own updates too');
assert.equal(calls.notifications.length, 1, 'own actions must not notify the same user');

handle({ old: { id: 'missing-new-row' } }, 'message');
assert.equal(calls.refreshes.length, 3, 'events without a new row are ignored');

process.stdout.write('Workspace Realtime activity refresh tests passed.\n');
