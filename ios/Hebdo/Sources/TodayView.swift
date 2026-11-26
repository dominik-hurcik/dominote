import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: NoteStore
    @AppStorage("hebdo.calMode") private var calModeRaw = CalendarMode.daily.rawValue

    @State private var selectedDate = Date()
    @State private var showMonthGrid = false
    @State private var displayYear = Calendar.current.component(.year, from: Date())
    @State private var displayMonth = Calendar.current.component(.month, from: Date())
    @State private var showSettings = false

    private var calMode: CalendarMode { CalendarMode(rawValue: calModeRaw) ?? .daily }
    private var todayKey: String { CalendarHelper.dateKey(Date()) }
    private var selectedKey: String { CalendarHelper.dateKey(selectedDate) }
    private var selectedWeekKey: String { CalendarHelper.isoWeekInfo(selectedDate).key }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                calendarHeader
                Rectangle().fill(HebdoTheme.border).frame(height: 0.5)
                let target = CalendarHelper.calendarNote(for: selectedDate, mode: calMode)
                NoteEditorView(
                    initialPath: target.path,
                    draftTemplate: store.exists(target.path) ? nil : target.template,
                    allowTitleEdit: false
                )
                .id("\(target.path)-\(calMode.rawValue)")
            }
            .background(HebdoTheme.bg)
            .toolbarBackground(HebdoTheme.side, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedDate = Date()
                            displayYear = Calendar.current.component(.year, from: selectedDate)
                            displayMonth = Calendar.current.component(.month, from: selectedDate)
                        }
                    } label: {
                        Text(CalendarHelper.monthTitle(year: displayYear, month: displayMonth))
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(HebdoTheme.text)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                showMonthGrid.toggle()
                            }
                        } label: {
                            Image(systemName: showMonthGrid ? "chevron.up" : "calendar")
                                .font(.system(size: 15))
                                .foregroundStyle(HebdoTheme.muted)
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15))
                                .foregroundStyle(HebdoTheme.muted)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Editorial Week Strip / Expandable Month Grid

    private var calendarHeader: some View {
        VStack(spacing: 5) {
            if showMonthGrid {
                HStack {
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13))
                            .foregroundStyle(HebdoTheme.muted)
                            .frame(width: 28, height: 26)
                    }
                    Spacer()
                    Button {
                        selectedDate = Date()
                        displayYear = Calendar.current.component(.year, from: selectedDate)
                        displayMonth = Calendar.current.component(.month, from: selectedDate)
                    } label: {
                        Text("Today")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(HebdoTheme.muted)
                    }
                    Spacer()
                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(HebdoTheme.muted)
                            .frame(width: 28, height: 26)
                    }
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 0) {
                Text("W")
                    .frame(width: 26)
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                    Text(label)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 10, weight: .medium, design: .serif))
            .foregroundStyle(HebdoTheme.faint)
            .padding(.horizontal, 10)

            let rows = showMonthGrid
                ? CalendarHelper.monthGrid(year: displayYear, month: displayMonth)
                : [CalendarHelper.weekDays(containing: selectedDate)]

            ForEach(rows) { row in
                weekRowView(row)
            }
        }
        .padding(.vertical, 8)
        .background(HebdoTheme.side)
    }

    private func weekRowView(_ row: CalendarWeekRow) -> some View {
        let isWeekSelected = calMode == .weekly && row.key == selectedWeekKey
        let weekHasNote = store.journalPaths.contains("Journal/\(row.key).md")

        return HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("\(row.week)")
                    .font(.system(size: 10, design: .serif).monospacedDigit())
                    .foregroundStyle(HebdoTheme.faint)
                Circle()
                    .fill(weekHasNote && calMode == .weekly ? HebdoTheme.accent : Color.clear)
                    .frame(width: 3.5, height: 3.5)
            }
            .frame(width: 26)

            ForEach(row.days) { day in
                let isSelected = calMode == .daily && day.key == selectedKey
                let isToday = day.key == todayKey
                let hasNote = store.journalPaths.contains("Journal/\(day.key).md")

                Button {
                    selectedDate = day.date
                    displayYear = Calendar.current.component(.year, from: day.date)
                    displayMonth = Calendar.current.component(.month, from: day.date)
                } label: {
                    VStack(spacing: 2) {
                        Text("\(Calendar.current.component(.day, from: day.date))")
                            .font(.system(size: 14, weight: isToday || isSelected ? .bold : .regular, design: .serif).monospacedDigit())
                            .foregroundStyle(
                                isToday ? HebdoTheme.accent :
                                day.inMonth || !showMonthGrid ? HebdoTheme.text : HebdoTheme.faint.opacity(0.6)
                            )
                            .frame(width: 30, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? HebdoTheme.active : Color.clear)
                            )

                        Circle()
                            .fill(hasNote && calMode == .daily ? HebdoTheme.accent : Color.clear)
                            .frame(width: 3.5, height: 3.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isWeekSelected ? HebdoTheme.active : Color.clear)
                .padding(.horizontal, 8)
        )
    }

    private func shiftMonth(_ delta: Int) {
        var m = displayMonth + delta
        var y = displayYear
        if m < 1 { m = 12; y -= 1 }
        else if m > 12 { m = 1; y += 1 }
        displayMonth = m
        displayYear = y
    }
}
