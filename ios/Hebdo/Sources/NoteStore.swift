import Foundation
import Combine

struct NoteNode: Identifiable, Hashable {
    let name: String
    let path: String // relative to root, e.g. "Projects/Launch plan.md"
    let isDir: Bool
    var children: [NoteNode]

    var id: String { path }
}

struct SearchHit: Identifiable, Hashable {
    let path: String
    let title: String
    let snippet: String

    var id: String { path }
}

enum SyncSource: Equatable {
    case iCloudDrive
    case customFolder(String)
    case localDevice

    var label: String {
        switch self {
        case .iCloudDrive: return "iCloud Drive / Hebdo"
        case .customFolder(let name): return "Folder: \(name)"
        case .localDevice: return "On This iPhone (Local)"
        }
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published var tree: [NoteNode] = []
    @Published var journalPaths: Set<String> = []
    @Published var syncSource: SyncSource = .localDevice
    @Published var errorMessage: String?

    private static let bookmarkKey = "hebdo.customFolderBookmark"
    private static let ubiquityID = "iCloud.app.hebdo"

    private var rootURL: URL
    private var scopedURL: URL?
    private var metadataQuery: NSMetadataQuery?

    init() {
        self.rootURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        resolveRoot()
        refreshTree()
        startMonitoringIfNeeded()
    }

    deinit {
        metadataQuery?.stop()
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Root resolution (Custom bookmark -> iCloud Drive/Hebdo -> Local Documents)

    func resolveRoot() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil

        if let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                scopedURL = url
                rootURL = url
                syncSource = .customFolder(url.lastPathComponent)
                return
            }
        }

        if let container = FileManager.default.url(forUbiquityContainerIdentifier: Self.ubiquityID) {
            let docs = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            rootURL = docs
            syncSource = .iCloudDrive
            return
        }

        let local = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hebdo", isDirectory: true)
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        rootURL = local
        syncSource = .localDevice
    }

    func setCustomFolder(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            resolveRoot()
            refreshTree()
            startMonitoringIfNeeded()
        } catch {
            errorMessage = "Could not save folder access: \(error.localizedDescription)"
        }
    }

    func resetToDefaultFolder() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        resolveRoot()
        refreshTree()
        startMonitoringIfNeeded()
    }

    // MARK: - iCloud live monitoring

    private func startMonitoringIfNeeded() {
        metadataQuery?.stop()
        metadataQuery = nil
        guard syncSource == .iCloudDrive else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMetadataUpdate() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMetadataUpdate() }
        }

        query.start()
        metadataQuery = query
    }

    private func handleMetadataUpdate() {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        for case let item as NSMetadataItem in query.results {
            if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                }
            }
        }
        refreshTree()
    }

    // MARK: - Tree & Files

    func fileURL(for relPath: String) -> URL {
        rootURL.appendingPathComponent(relPath)
    }

    func exists(_ relPath: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: relPath).path)
    }

    func refreshTree() {
        var journals = Set<String>()
        let nodes = walk(dir: rootURL, prefix: "", depth: 0, journals: &journals)
        tree = nodes
        journalPaths = journals
    }

    private func walk(dir: URL, prefix: String, depth: Int, journals: inout Set<String>) -> [NoteNode] {
        guard depth < 12 else { return [] }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [NoteNode] = []
        for url in items {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let rel = prefix.isEmpty ? name : "\(prefix)/\(name)"

            if isDir {
                if name == "Sketches" && prefix.isEmpty { continue } // v1 iOS focuses on Markdown notes
                let children = walk(dir: url, prefix: rel, depth: depth + 1, journals: &journals)
                out.append(NoteNode(name: name, path: rel, isDir: true, children: children))
            } else if name.hasSuffix(".md") {
                let title = String(name.dropLast(3))
                if rel.hasPrefix("Journal/") { journals.insert(rel) }
                out.append(NoteNode(name: title, path: rel, isDir: false, children: []))
            }
        }
        out.sort { a, b in
            if a.isDir != b.isDir { return a.isDir && !b.isDir }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return out
    }

    // MARK: - Coordinated Read / Write / CRUD

    func readNote(at relPath: String) -> String {
        let url = fileURL(for: relPath)
        var result = ""
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { target in
            result = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        }
        return result
    }

    func writeNote(at relPath: String, content: String) {
        let url = fileURL(for: relPath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            do {
                try content.write(to: target, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let err = coordError ?? writeError {
            errorMessage = "Save failed: \(err.localizedDescription)"
        } else {
            refreshTree()
        }
    }

    func createNote(in dir: String = "") -> String {
        let baseDir = dir.isEmpty ? rootURL : fileURL(for: dir)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        var name = "Untitled"
        var i = 2
        while FileManager.default.fileExists(atPath: baseDir.appendingPathComponent("\(name).md").path) {
            name = "Untitled \(i)"
            i += 1
        }
        let rel = dir.isEmpty ? "\(name).md" : "\(dir)/\(name).md"
        writeNote(at: rel, content: "")
        return rel
    }

    func createFolder(in dir: String = "", named rawName: String) {
        let cleaned = cleanName(rawName)
        guard !cleaned.isEmpty else { return }
        let baseDir = dir.isEmpty ? rootURL : fileURL(for: dir)
        let target = baseDir.appendingPathComponent(cleaned, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        refreshTree()
    }

    func renameNote(from relPath: String, to newTitle: String) -> String? {
        let cleaned = cleanName(newTitle)
        guard !cleaned.isEmpty else { return nil }
        let oldURL = fileURL(for: relPath)
        let dir = (relPath as NSString).deletingLastPathComponent
        let newRel = dir.isEmpty ? "\(cleaned).md" : "\(dir)/\(cleaned).md"
        if newRel == relPath { return relPath }
        let newURL = fileURL(for: newRel)
        if FileManager.default.fileExists(atPath: newURL.path),
           newURL.path.lowercased() != oldURL.path.lowercased() {
            errorMessage = "A page named “\(cleaned)” already exists."
            return nil
        }
        var coordError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(writingItemAt: oldURL, options: .forMoving, writingItemAt: newURL, options: .forReplacing, error: &coordError) { src, dst in
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                moveError = error
            }
        }
        if let err = coordError ?? moveError {
            errorMessage = "Rename failed: \(err.localizedDescription)"
            return nil
        }
        refreshTree()
        return newRel
    }

    func deleteItem(at relPath: String) {
        let url = fileURL(for: relPath)
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { target in
            try? FileManager.default.removeItem(at: target)
        }
        refreshTree()
    }

    func search(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var flat: [NoteNode] = []
        func flatten(_ list: [NoteNode]) {
            for n in list {
                if n.isDir { flatten(n.children) }
                else { flat.append(n) }
            }
        }
        flatten(tree)

        if q.isEmpty {
            return flat.prefix(30).map { SearchHit(path: $0.path, title: $0.name, snippet: $0.path) }
        }

        var titleHits: [SearchHit] = []
        var bodyHits: [SearchHit] = []
        for n in flat {
            if n.name.lowercased().contains(q) {
                titleHits.append(SearchHit(path: n.path, title: n.name, snippet: n.path))
            } else {
                let body = readNote(at: n.path)
                if let range = body.range(of: q, options: .caseInsensitive) {
                    let lineRange = body.lineRange(for: range)
                    let snippet = String(body[lineRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    bodyHits.append(SearchHit(path: n.path, title: n.name, snippet: String(snippet.prefix(90))))
                }
            }
        }
        return Array((titleHits + bodyHits).prefix(50))
    }

    private func cleanName(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: bad)
        let joined = parts.joined(separator: "-")
        if joined.hasPrefix(".") { return "" }
        return joined
    }
}
