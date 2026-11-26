import SwiftUI

struct NotesListView: View {
    @EnvironmentObject private var store: NoteStore
    @State private var query = ""
    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var activeNotePath: String?

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    let hits = store.search(query)
                    if hits.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(HebdoTheme.bg)
                    } else {
                        ForEach(hits) { hit in
                            NavigationLink(value: hit.path) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hit.title)
                                        .font(.system(size: 16, weight: .medium, design: .serif))
                                        .foregroundStyle(HebdoTheme.text)
                                    Text(hit.snippet)
                                        .font(.system(size: 12, design: .serif))
                                        .foregroundStyle(HebdoTheme.faint)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowBackground(HebdoTheme.bg)
                        }
                    }
                } else if store.tree.isEmpty {
                    ContentUnavailableView(
                        "No Notes Yet",
                        systemImage: "doc.text",
                        description: Text("Tap + to create a note, or point Hebdo Mac at iCloud Drive / Hebdo to sync.")
                    )
                    .listRowBackground(HebdoTheme.bg)
                } else {
                    NodeRowsView(nodes: store.tree, parentDir: "")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(HebdoTheme.side)
            .navigationTitle("Notes")
            .searchable(text: $query, prompt: "Search pages…")
            .refreshable { store.refreshTree() }
            .navigationDestination(for: String.self) { path in
                NoteEditorView(initialPath: path, draftTemplate: nil, allowTitleEdit: true)
            }
            .navigationDestination(item: $activeNotePath) { path in
                NoteEditorView(initialPath: path, draftTemplate: nil, allowTitleEdit: true)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(HebdoTheme.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeNotePath = store.createNote()
                        } label: {
                            Label("New Page", systemImage: "doc.badge.plus")
                        }
                        Button {
                            newFolderName = ""
                            showNewFolder = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(HebdoTheme.text)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") { store.createFolder(named: newFolderName) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private struct NodeRowsView: View {
    @EnvironmentObject private var store: NoteStore
    let nodes: [NoteNode]
    let parentDir: String

    var body: some View {
        ForEach(nodes) { node in
            if node.isDir {
                NavigationLink {
                    FolderView(folder: node)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundStyle(HebdoTheme.muted)
                        Text(node.name)
                            .font(.system(size: 16, design: .serif))
                            .foregroundStyle(HebdoTheme.text)
                        Spacer()
                        Text("\(node.children.count)")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(HebdoTheme.faint)
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(HebdoTheme.side)
                .listRowSeparatorTint(HebdoTheme.border.opacity(0.6))
            } else {
                NavigationLink(value: node.path) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14))
                            .foregroundStyle(HebdoTheme.muted)
                        Text(node.name)
                            .font(.system(size: 16, design: .serif))
                            .foregroundStyle(HebdoTheme.text)
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(HebdoTheme.side)
                .listRowSeparatorTint(HebdoTheme.border.opacity(0.6))
            }
        }
        .onDelete { offsets in
            for idx in offsets {
                store.deleteItem(at: nodes[idx].path)
            }
        }
    }
}

private struct FolderView: View {
    @EnvironmentObject private var store: NoteStore
    let folder: NoteNode
    @State private var activeNotePath: String?

    private var liveChildren: [NoteNode] {
        find(path: folder.path, in: store.tree)?.children ?? folder.children
    }

    var body: some View {
        List {
            if liveChildren.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder")
                    .listRowBackground(HebdoTheme.side)
            } else {
                NodeRowsView(nodes: liveChildren, parentDir: folder.path)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HebdoTheme.side)
        .navigationTitle(folder.name)
        .navigationDestination(item: $activeNotePath) { path in
            NoteEditorView(initialPath: path, draftTemplate: nil, allowTitleEdit: true)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeNotePath = store.createNote(in: folder.path)
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .foregroundStyle(HebdoTheme.text)
                }
            }
        }
    }

    private func find(path: String, in list: [NoteNode]) -> NoteNode? {
        for n in list {
            if n.path == path { return n }
            if n.isDir, let hit = find(path: path, in: n.children) { return hit }
        }
        return nil
    }
}
