import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: NoteStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("hebdo.theme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("hebdo.calMode") private var calModeRaw = CalendarMode.daily.rawValue
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { t in
                            Text(t.label).tag(t.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Calendar") {
                    Picker("Calendar Notes", selection: $calModeRaw) {
                        ForEach(CalendarMode.allCases) { m in
                            Text(m.label).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text("Notes Folder")
                        Spacer()
                        Text(store.syncSource.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button("Choose Folder from Files…") {
                        showFolderPicker = true
                    }

                    if case .customFolder = store.syncSource {
                        Button("Reset to iCloud Drive / Hebdo", role: .destructive) {
                            store.resetToDefaultFolder()
                        }
                    }
                } header: {
                    Text("Sync (Zero Servers)")
                } footer: {
                    Text("Your notes are plain Markdown files. Point Hebdo on your Mac at iCloud Drive / Hebdo (or pick any shared folder) to sync automatically with no login.")
                }

                Section("About") {
                    HStack {
                        Text("Hebdo")
                        Spacer()
                        Text("hebdo.app")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { url in
                    store.setCustomFolder(url)
                }
            }
        }
    }
}

private struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
    }
}
