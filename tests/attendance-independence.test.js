const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('semester-upgrade.js', 'utf8');
const required = [
  'd.attendanceCoursesInitialized',
  "type:c.type==='Lab'?'Lab':'Lecture'",
  "a.status==='Approved Leave'",
  "status==='Approved Leave'?'Approved leave recorded; it will not count as an absence.'",
  "['Present','Absent','Approved Leave','Cancelled']",
  'd.attendanceCourses.map(g=>({g,s:attStats(g.id)}))'
];
for (const marker of required) {
  assert.ok(source.includes(marker), 'missing attendance behavior: ' + marker);
}

function runAttendance(data) {
  data.grades = Array.isArray(data.grades) ? data.grades : [];
  data.tasks = Array.isArray(data.tasks) ? data.tasks : [];
  data.assessments = Array.isArray(data.assessments) ? data.assessments : [];
  data.semesterGoal = data.semesterGoal ?? 70;
  data.attendanceMinimum = data.attendanceMinimum ?? 75;
  const nodes = {};
  for (const id of [
    'attendanceOverall','attendanceSessions','attendanceAtRisk',
    'attendanceThreshold','attendanceMinimumInput','attendanceCourseList',
    'dashboardAttendanceOverall','dashboardAttendanceClasses','dashboardAttendanceSessions','dashboardApprovedLeave',
    'attendanceQuickList','attendanceHistory'
  ]) nodes[id] = { textContent: '', innerHTML: '', value: '' };
  const api = {
    data,
    save() {},
    toast() {},
    esc(value) { return String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); },
    uid() { return 'new-course-id'; },
    today() { return '2026-11-14'; },
    switchPage() {}
  };
  const document = {
    getElementById(id) { return nodes[id] || null; },
    querySelectorAll() { return []; }
  };
  const window = { UniPlannerSemester: api };
  const context = vm.createContext({ window, document, console, confirm: () => true, FormData });
  vm.runInContext(source, context, { filename: 'semester-upgrade.js' });
  window.UniPlannerSemester.init();
  return { api: window.UniPlannerSemester, nodes };
}

{
  const data = {
    grades: [{ id: 'course-programming', course: 'Programming Fundamentals', credits: 3 }],
    attendance: [
      { id: 'a1', subjectId: 'course-programming', course: 'Programming Fundamentals', date: '2026-11-10', status: 'Present' },
      { id: 'a2', subjectId: 'course-programming', course: 'Programming Fundamentals', date: '2026-11-11', status: 'Absent' },
      { id: 'a3', subjectId: 'course-programming', course: 'Programming Fundamentals', date: '2026-11-12', status: 'Approved Leave' },
      { id: 'a4', subjectId: 'course-programming', course: 'Programming Fundamentals', date: '2026-11-13', status: 'Cancelled' }
    ]
  };
  const { api, nodes } = runAttendance(data);
  assert.equal(nodes.attendanceOverall.textContent, '50%', 'approved leave and cancelled classes must not affect the percentage');
  assert.equal(nodes.attendanceSessions.textContent, 2, 'only present and absent sessions count');
  assert.equal(nodes.dashboardAttendanceOverall.textContent, '50%');
  assert.equal(nodes.dashboardAttendanceClasses.textContent, 1);
  assert.equal(nodes.dashboardAttendanceSessions.textContent, 2);
  assert.equal(nodes.dashboardApprovedLeave.textContent, 1);
  assert.match(nodes.attendanceQuickList.innerHTML, /1 approved leave/);
  assert.match(nodes.attendanceHistory.innerHTML, /Approved Leave/);
  assert.equal(data.attendanceCourses[0].id, 'course-programming', 'legacy attendance subject IDs must be preserved');

  data.grades = [];
  api.render();
  assert.match(nodes.attendanceQuickList.innerHTML, /Programming Fundamentals/, 'attendance classes must remain after Grades is empty');
}

{
  const data = {
    grades: [],
    attendanceCourses: [
      { id: 'lecture-1', name: 'Applied Physics', type: 'Lecture' },
      { id: 'lab-1', name: 'Applied Physics', type: 'Lab' }
    ],
    attendanceCoursesInitialized: true,
    attendance: [
      { id: 'l1', subjectId: 'lecture-1', course: 'Applied Physics', status: 'Present', date: '2026-11-10' },
      { id: 'l2', subjectId: 'lab-1', course: 'Applied Physics', status: 'Absent', date: '2026-11-10' }
    ]
  };
  const { nodes } = runAttendance(data);
  assert.equal(nodes.attendanceOverall.textContent, '50%');
  assert.match(nodes.attendanceQuickList.innerHTML, /Lecture/);
  assert.match(nodes.attendanceQuickList.innerHTML, /Lab/);
  assert.equal(data.attendanceCourses.length, 2, 'lecture and lab records must remain separate even for the same course name');
}

{
  const data = {
    grades: [{ id: 'legacy', course: 'Functional English', credits: 3 }],
    attendance: [],
    attendanceCourses: [],
    attendanceCoursesInitialized: true
  };
  const { api } = runAttendance(data);
  assert.equal(data.attendanceCourses.length, 0, 'an intentionally empty attendance list must not be repopulated from Grades');
  api.render();
  assert.equal(data.attendanceCourses.length, 0);
}

process.stdout.write('Attendance independence and approved-leave tests passed.\\n');
