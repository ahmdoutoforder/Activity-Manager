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

const queueStart = html.indexOf('let workspaceActivityRefreshTimer = null;');
const queueEnd = html.indexOf('\nfunction handleWorkspaceCollaborationRealtime', queueStart);
assert.ok(queueStart >= 0 && queueEnd > queueStart, 'workspace activity debounce helper must exist');
const queued = [];
const cleared = [];
const rendered = [];
const workspace = { id: 'workspace-1' };
const activityPanel = {};
const sections = { workspaceId: workspace.id, activity: activityPanel };
const queueContext = vm.createContext({
  workspaceHubSections: sections,
  activeWorkspaceId: workspace.id,
  user: { id: 'self' },
  accessGranted: true,
  workspaces: [workspace],
  clearTimeout: id => cleared.push(id),
  setTimeout: (callback, delay) => {
    const id = queued.length + 1;
    queued.push({ id, callback, delay });
    return id;
  },
  renderWorkspaceActivity: (currentWorkspace, panel) => rendered.push([currentWorkspace.id, panel])
});
vm.runInContext(
  html.slice(queueStart, queueEnd) + '\nthis.queueWorkspaceActivityRefresh = queueWorkspaceActivityRefresh;',
  queueContext
);
queueContext.queueWorkspaceActivityRefresh(workspace.id);
queueContext.queueWorkspaceActivityRefresh(workspace.id);
assert.equal(queued.length, 2, 'rapid events should replace the pending refresh');
assert.deepEqual(cleared, [1], 'the previous timer should be cancelled when a new event arrives');
assert.equal(queued[1].delay, 350, 'the activity refresh should be briefly debounced');
queued[1].callback();
assert.deepEqual(rendered, [['workspace-1', activityPanel]], 'the selected workspace activity panel should refresh once');

queueContext.queueWorkspaceActivityRefresh('another-workspace');
assert.equal(queued.length, 2, 'events from unselected workspaces must not schedule a refresh');
queueContext.queueWorkspaceActivityRefresh(workspace.id);
queueContext.activeWorkspaceId = 'another-workspace';
queued[2].callback();
assert.equal(rendered.length, 1, 'a stale timer must not refresh after switching workspaces');

const subscriptionStart = html.indexOf('function startGroupNotificationFeed()');
const subscriptionEnd = html.indexOf('function syncUi()', subscriptionStart);
assert.ok(subscriptionStart >= 0 && subscriptionEnd > subscriptionStart, 'the existing Realtime channel must exist');
const subscriptionSource = html.slice(subscriptionStart, subscriptionEnd);
for (const table of ['uniplanner_group_messages', 'uniplanner_task_comments', 'uniplanner_shared_tasks']) {
  assert.ok(subscriptionSource.includes("table: '" + table + "'"), 'Realtime should continue listening to ' + table);
}
assert.ok(subscriptionSource.includes("handleWorkspaceCollaborationRealtime(payload, 'message')"));
assert.ok(subscriptionSource.includes("handleWorkspaceCollaborationRealtime(payload, 'comment')"));
assert.ok(subscriptionSource.includes("handleWorkspaceCollaborationRealtime(payload, 'task')"));
assert.match(subscriptionSource, /if \(!supa \|\| !user \|\| !accessGranted\) return;/);
assert.doesNotMatch(
  subscriptionSource.slice(0, subscriptionSource.indexOf('groupNotificationChannel = supa.channel')),
  /prefs\.groupNotifications|Notification\.permission/,
  'the live foreground feed must not be gated by browser notification settings'
);

process.stdout.write('Workspace Realtime activity refresh tests passed.\n');
