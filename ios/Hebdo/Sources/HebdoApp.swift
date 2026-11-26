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
    @AppStorage("hebdo.calMode") private var calModeRaw = CalendarMode.daily.rawValue

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
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
            .environmentObject(store)
            .preferredColorScheme(theme.colorScheme)
            .tint(HebdoTheme.text)
        }
    }
}
