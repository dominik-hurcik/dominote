import Foundation

enum CalendarMode: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }
    var label: String { self == .daily ? "Daily" : "Weekly" }
}

struct CalendarDay: Identifiable, Hashable {
    let date: Date
    let key: String
    let inMonth: Bool

    var id: String { key }
}

struct CalendarWeekRow: Identifiable {
    let week: Int
    let key: String
    let days: [CalendarDay]

    var id: String { key }
}

enum CalendarHelper {
    static let isoCalendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        cal.timeZone = .current
        return cal
    }()

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let daysFull = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static func dateKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    static func isoWeekInfo(_ date: Date) -> (year: Int, week: Int, key: String, monday: Date, sunday: Date) {
        let comps = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 2026
        let week = comps.weekOfYear ?? 1
        let key = String(format: "%04d-W%02d", year, week)

        let startOfDay = Calendar.current.startOfDay(for: date)
        let weekday = Calendar.current.component(.weekday, from: startOfDay) // Sun=1 .. Sat=7
        let offsetToMon = (weekday + 5) % 7
        let monday = Calendar.current.date(byAdding: .day, value: -offsetToMon, to: startOfDay) ?? startOfDay
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? monday
        return (year, week, key, monday, sunday)
    }

    static func weekDays(containing date: Date) -> CalendarWeekRow {
        let info = isoWeekInfo(date)
        let month = Calendar.current.component(.month, from: date)
        let days = (0..<7).compactMap { offset -> CalendarDay? in
            guard let d = Calendar.current.date(byAdding: .day, value: offset, to: info.monday) else { return nil }
            let m = Calendar.current.component(.month, from: d)
            return CalendarDay(date: d, key: dateKey(d), inMonth: m == month)
        }
        return CalendarWeekRow(week: info.week, key: info.key, days: days)
    }

    static func monthGrid(year: Int, month: Int) -> [CalendarWeekRow] {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = Calendar.current.date(from: comps) else { return [] }
        let weekday = Calendar.current.component(.weekday, from: first)
        let offset = (weekday + 5) % 7
        guard let start = Calendar.current.date(byAdding: .day, value: -offset, to: first) else { return [] }

        var rows: [CalendarWeekRow] = []
        for w in 0..<6 {
            var days: [CalendarDay] = []
            for i in 0..<7 {
                if let d = Calendar.current.date(byAdding: .day, value: w * 7 + i, to: start) {
                    let m = Calendar.current.component(.month, from: d)
                    days.append(CalendarDay(date: d, key: dateKey(d), inMonth: m == month))
                }
            }
            guard let firstDay = days.first else { continue }
            let info = isoWeekInfo(firstDay.date)
            rows.append(CalendarWeekRow(week: info.week, key: info.key, days: days))
        }
        if rows.count == 6, rows[5].days.allSatisfy({ !$0.inMonth }) {
            rows.removeLast()
        }
        return rows
    }

    static func monthTitle(year: Int, month: Int) -> String {
        let idx = max(0, min(11, month - 1))
        return "\(months[idx]) \(year)"
    }

    static func dailyNote(for date: Date) -> (path: String, title: String, template: String) {
        let key = dateKey(date)
        let cal = Calendar.current
        let dow = cal.component(.weekday, from: date) - 1
        let m = cal.component(.month, from: date) - 1
        let day = cal.component(.day, from: date)
        let year = cal.component(.year, from: date)
        let label = "\(daysFull[max(0, min(6, dow))]), \(months[max(0, min(11, m))]) \(day), \(year)"
        let template = """
        \(label)

        ## Tasks

        - [ ] 

        ## Notes

        """
        return ("Journal/\(key).md", key, template)
    }

    static func weeklyNote(for date: Date) -> (path: String, title: String, template: String) {
        let info = isoWeekInfo(date)
        let cal = Calendar.current
        let m1 = months[cal.component(.month, from: info.monday) - 1]
        let m2 = months[cal.component(.month, from: info.sunday) - 1]
        let d1 = cal.component(.day, from: info.monday)
        let d2 = cal.component(.day, from: info.sunday)
        let y1 = cal.component(.year, from: info.monday)
        let y2 = cal.component(.year, from: info.sunday)
        let range: String
        if y1 != y2 {
            range = "\(m1) \(d1), \(y1) – \(m2) \(d2), \(y2)"
        } else if m1 == m2 {
            range = "\(m1) \(d1) – \(d2), \(y2)"
        } else {
            range = "\(m1) \(d1) – \(m2) \(d2), \(y2)"
        }
        let template = """
        \(range)

        ## Focus

        - [ ] 

        ## Monday

        ## Tuesday

        ## Wednesday

        ## Thursday

        ## Friday

        ## Weekend

        """
        return ("Journal/\(info.key).md", info.key, template)
    }

    static func calendarNote(for date: Date, mode: CalendarMode) -> (path: String, title: String, template: String) {
        mode == .daily ? dailyNote(for: date) : weeklyNote(for: date)
    }
}
