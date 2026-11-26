// ISO-8601 calendar & weekly/daily note helpers. Kept DOM-free so it can be tested with plain Node.
(function (exports) {
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const DAYS_FULL = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  const pad2 = n => String(n).padStart(2, '0');

  function dateKey(d) {
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  }

  /** ISO-8601 week { year, week, key: "YYYY-Www", monday: Date, sunday: Date } */
  function isoWeek(d) {
    const local = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    const dow = (local.getDay() + 6) % 7; // Mon=0 .. Sun=6
    const monday = new Date(local);
    monday.setDate(local.getDate() - dow);
    const sunday = new Date(monday);
    sunday.setDate(monday.getDate() + 6);
    const thu = new Date(monday);
    thu.setDate(monday.getDate() + 3);
    const year = thu.getFullYear();
    const jan4 = new Date(year, 0, 4);
    const jan4Dow = (jan4.getDay() + 6) % 7;
    const week1Mon = new Date(year, 0, 4 - jan4Dow);
    const week = Math.round((monday - week1Mon) / (7 * 86400000)) + 1;
    return { year, week, key: `${year}-W${pad2(week)}`, monday, sunday };
  }

  /** Returns array of 6 week rows (Mon..Sun) for the given year & 0-indexed month. */
  function monthGrid(year, month) {
    const first = new Date(year, month, 1);
    const offset = (first.getDay() + 6) % 7;
    const start = new Date(year, month, 1 - offset);
    const weeks = [];
    for (let w = 0; w < 6; w++) {
      const days = [];
      for (let i = 0; i < 7; i++) {
        const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + w * 7 + i);
        days.push({ date: d, key: dateKey(d), inMonth: d.getMonth() === month });
      }
      const info = isoWeek(days[0].date);
      weeks.push({ week: info.week, key: info.key, days });
    }
    // Trim 6th row if every day is in the next month.
    if (weeks[5].days.every(x => !x.inMonth)) weeks.pop();
    return weeks;
  }

  function formatRange(mon, sun) {
    const m1 = MONTHS[mon.getMonth()], m2 = MONTHS[sun.getMonth()];
    if (mon.getFullYear() !== sun.getFullYear()) {
      return `${m1} ${mon.getDate()}, ${mon.getFullYear()} – ${m2} ${sun.getDate()}, ${sun.getFullYear()}`;
    }
    if (m1 === m2) return `${m1} ${mon.getDate()} – ${sun.getDate()}, ${sun.getFullYear()}`;
    return `${m1} ${mon.getDate()} – ${m2} ${sun.getDate()}, ${sun.getFullYear()}`;
  }

  function weeklyNote(d) {
    const { key, monday, sunday } = isoWeek(d);
    const path = `Journal/${key}.md`;
    const template = `${formatRange(monday, sunday)}

## Focus

- [ ] 

## Monday

## Tuesday

## Wednesday

## Thursday

## Friday

## Weekend
`;
    return { key, path, template };
  }

  function dailyNote(d) {
    const key = dateKey(d);
    const path = `Journal/${key}.md`;
    const label = `${DAYS_FULL[d.getDay()]}, ${MONTHS[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
    const template = `${label}

## Tasks

- [ ] 

## Notes
`;
    return { key, path, template };
  }

  exports.CAL = { MONTHS, dateKey, isoWeek, monthGrid, formatRange, weeklyNote, dailyNote };
})(typeof module !== 'undefined' ? module.exports : window);
