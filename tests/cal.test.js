// ISO-8601 week and calendar grid tests. Run: node tests/cal.test.js
const assert = require('assert');
const { CAL } = require('../ui/cal.js');

// Standard date: Thu Nov 26, 2026 -> 2026-W48 (Mon Nov 23 – Sun Nov 29)
const w48 = CAL.isoWeek(new Date(2026, 10, 26));
assert.strictEqual(w48.key, '2026-W48');
assert.strictEqual(CAL.dateKey(w48.monday), '2026-11-23');
assert.strictEqual(CAL.dateKey(w48.sunday), '2026-11-29');

// ISO year boundary: Thu Dec 31, 2026 is in 2026-W53
assert.strictEqual(CAL.isoWeek(new Date(2026, 11, 31)).key, '2026-W53');
// Fri Jan 1, 2027 is ALSO in 2026-W53 (ISO rule: week belongs to Thursday's year)
assert.strictEqual(CAL.isoWeek(new Date(2027, 0, 1)).key, '2026-W53');
// Mon Jan 4, 2027 is 2027-W01
assert.strictEqual(CAL.isoWeek(new Date(2027, 0, 4)).key, '2027-W01');

// Month grid starts on Monday and has 5 or 6 rows of 7 days
const grid = CAL.monthGrid(2026, 10); // Nov 2026
assert.ok(grid.length === 5 || grid.length === 6);
grid.forEach(row => assert.strictEqual(row.days.length, 7));
assert.strictEqual(grid[0].days[0].date.getDay(), 1, 'grid must start on Monday');

// Templates
const wn = CAL.weeklyNote(new Date(2026, 10, 26));
assert.strictEqual(wn.path, 'Journal/2026-W48.md');
assert.ok(wn.template.includes('Nov 23 – 29, 2026'));

const dn = CAL.dailyNote(new Date(2026, 10, 26));
assert.strictEqual(dn.path, 'Journal/2026-11-26.md');
assert.ok(dn.template.includes('Thursday, Nov 26, 2026'));

console.log('cal ok');
