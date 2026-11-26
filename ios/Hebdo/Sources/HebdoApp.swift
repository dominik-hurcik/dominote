import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct HebdoApp: App {
    @StateObject private var store = NoteStore()
    @AppStorage("hebdo.theme") private var themeRaw = AppTheme.system.rawValue

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environmentObject(store)
                .preferredColorScheme(theme.colorScheme)
                .tint(HebdoTheme.text)
        }
    }
}

/// Compact screens (iPhone portrait) use Today + Notes tabs;
/// Regular screens (unfolded iPhone Duo, iPad) use a desktop-style 2-column split with bottom-left calendar.
private struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hebdo.calMode") private var calModeRaw = CalendarMode.daily.rawValue

    var body: some View {
        if sizeClass == .regular {
            RegularSplitView()
        } else {
            TabView {
                TodayView()
                    .tabItem {
                        Label(calModeRaw == CalendarMode.weekly.rawValue ? "This Week" : "Today", systemImage: "calendar")
                    }

                NotesListView()
                    .tabItem {
                        Label("Notes", systemImage: "doc.text")
                    }
            }
        }
    }
}

private struct RegularSplitView: View {
    @EnvironmentObject private var store: NoteStore
    @AppStorage("hebdo.calMode") private var calModeRaw = CalendarMode.daily.rawValue

    @State private var selectedPath: String?
    @State private var draftTemplate: String?
    @State private var allowTitleEdit = false
    @State private var query = ""
    @State private var calYear = Calendar.current.component(.year, from: Date())
    @State private var calMonth = Calendar.current.component(.month, from: Date())
    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    private var calMode: CalendarMode { CalendarMode(rawValue: calModeRaw) ?? .daily }
    private var todayKey: String { CalendarHelper.dateKey(Date()) }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedPath) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(store.search(query)) { hit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.title)
                                    .font(.system(size: 15, weight: .medium, design: .serif))
                                    .foregroundStyle(HebdoTheme.text)
                                Text(hit.snippet)
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundStyle(HebdoTheme.faint)
                                    .lineLimit(1)
                            }
                            .tag(hit.path)
                            .listRowBackground(HebdoTheme.side)
                        }
                    } else {
                        OutlineGroup(store.tree, children: \.optionalChildren) { node in
                            if node.isDir {
                                Label(node.name, systemImage: "folder")
                                    .font(.system(size: 15, design: .serif))
                                    .foregroundStyle(HebdoTheme.text)
                            } else {
                                Label(node.name, systemImage: "doc.text")
                                    .font(.system(size: 15, design: .serif))
                                    .foregroundStyle(HebdoTheme.text)
                                    .tag(node.path)
                            }
                        }
                        .listRowBackground(HebdoTheme.side)

                        if !store.sketches.isEmpty {
                            Section("Sketches") {
                                ForEach(store.sketches) { sk in
                                    Label(sk.name, systemImage: "pencil.and.outline")
                                        .font(.system(size: 15, design: .serif))
                                        .foregroundStyle(HebdoTheme.text)
                                        .tag(sk.path)
                                        .listRowBackground(HebdoTheme.side)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(HebdoTheme.side)
                .searchable(text: $query, prompt: "Search pages…")
                .onChange(of: selectedPath) { _, newPath in
                    if let p = newPath, store.exists(p) {
                        draftTemplate = nil
                        allowTitleEdit = !p.hasPrefix("Journal/")
                    }
                }

                // Pinned bottom-left mini-calendar (matches desktop Hebdo)
                Rectangle().fill(HebdoTheme.border).frame(height: 0.5)
                sidebarCalendar
            }
            .background(HebdoTheme.side)
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(HebdoTheme.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { openCalendar(for: Date()) } label: {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(HebdoTheme.muted)
                        }
                        Menu {
                            Button {
                                let p = store.createNote()
                                draftTemplate = nil
                                allowTitleEdit = true
                                selectedPath = p
                            } label: {
                                Label("New Page", systemImage: "doc.badge.plus")
                            }
                            Button {
                                let p = store.createSketch()
                                draftTemplate = nil
                                allowTitleEdit = false
                                selectedPath = p
                            } label: {
                                Label("New Sketch", systemImage: "pencil.and.outline")
                            }
                            Button {
                                newFolderName = ""
                                showNewFolder = true
                            } label: {
                                Label("New Folder", systemImage: "folder.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus").foregroundStyle(HebdoTheme.text)
                        }
                    }
                }
            }
        } detail: {
            if let path = selectedPath {
                if NoteStore.isSketch(path) {
                    SketchEditorView(path: path)
                        .id(path)
                } else {
                    NoteEditorView(initialPath: path, draftTemplate: draftTemplate, allowTitleEdit: allowTitleEdit)
                        .id("\(path)-\(draftTemplate != nil)")
                }
            } else {
                Text("Select a note or pick a day")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(HebdoTheme.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HebdoTheme.bg)
            }
        }
        .onAppear {
            if selectedPath == nil { openCalendar(for: Date()) }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { store.createFolder(named: newFolderName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var sidebarCalendar: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    let now = Date()
                    calYear = Calendar.current.component(.year, from: now)
                    calMonth = Calendar.current.component(.month, from: now)
                } label: {
                    Text(CalendarHelper.monthTitle(year: calYear, month: calMonth))
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(HebdoTheme.text)
                }
                Spacer()
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11)).foregroundStyle(HebdoTheme.muted)
                }
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(HebdoTheme.muted)
                }
            }
            .padding(.horizontal, 10)

            HStack(spacing: 0) {
                Text("W").frame(width: 22)
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { Text($0).frame(maxWidth: .infinity) }
            }
            .font(.system(size: 10, design: .serif))
            .foregroundStyle(HebdoTheme.faint)
            .padding(.horizontal, 6)

            ForEach(CalendarHelper.monthGrid(year: calYear, month: calMonth)) { row in
                HStack(spacing: 0) {
                    Text("\(row.week)")
                        .font(.system(size: 9.5, design: .serif).monospacedDigit())
                        .foregroundStyle(HebdoTheme.faint)
                        .frame(width: 22)
                    ForEach(row.days) { day in
                        let path = "Journal/\(day.key).md"
                        let hasNote = store.journalPaths.contains(path)
                        let isSelected = selectedPath == path
                        let isToday = day.key == todayKey
                        Button { openCalendar(for: day.date) } label: {
                            VStack(spacing: 1) {
                                Text("\(Calendar.current.component(.day, from: day.date))")
                                    .font(.system(size: 12, weight: isToday || isSelected ? .bold : .regular, design: .serif).monospacedDigit())
                                    .foregroundStyle(isToday ? HebdoTheme.accent : day.inMonth ? HebdoTheme.text : HebdoTheme.faint.opacity(0.6))
                                    .frame(width: 24, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? HebdoTheme.active : Color.clear))
                                Circle()
                                    .fill(hasNote ? HebdoTheme.accent : Color.clear)
                                    .frame(width: 3, height: 3)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.vertical, 8)
        .background(HebdoTheme.side)
    }

    private func openCalendar(for date: Date) {
        let target = CalendarHelper.calendarNote(for: date, mode: calMode)
        draftTemplate = store.exists(target.path) ? nil : target.template
        allowTitleEdit = false
        selectedPath = target.path
    }

    private func shiftMonth(_ delta: Int) {
        var m = calMonth + delta
        var y = calYear
        if m < 1 { m = 12; y -= 1 }
        else if m > 12 { m = 1; y += 1 }
        calMonth = m
        calYear = y
    }
}

private extension NoteNode {
    var optionalChildren: [NoteNode]? { isDir ? children : nil }
}
