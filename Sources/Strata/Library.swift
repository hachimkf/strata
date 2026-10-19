import SwiftUI
import AppKit
import UserNotifications
import StrataCore

/// The app's single source of truth: watched folders and corrections in, clients and projects out.
/// Rescans when the disk changes.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var projects: [ProjectGroup] = []
    @Published private(set) var collections: [Client] = []
    @Published private(set) var hiddenCollections: [Client] = []
    @Published private(set) var standalone: [ProjectGroup] = []
    @Published private(set) var loose: [CreativeFile] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var fileCount = 0
    @Published private(set) var health = IndexHealth()
    @Published private(set) var folders: [URL]
    @Published private(set) var overrides: Overrides
    /// A short message shown at the bottom of the window ("Moved to Trash", "Copied #FF6B4A").
    @Published var toast: String?
    /// Whether the current toast offers Undo.
    @Published var toastUndo = false

    private var fileIndex: [String: CreativeFile] = [:]
    private let visual = VisualIndex(fileURL: VisualIndex.defaultURL())
    private let scanner = Scanner(cache: MetadataCache(fileURL: MetadataCache.defaultURL()))
    private var watcher: FolderWatcher?
    private var rescanQueued = false
    private var toastTask: Task<Void, Never>?
    private static let foldersKey = "watchedFolders"
    private static let knownRecoveredKey = "knownRecoveredFiles"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.foldersKey), !saved.isEmpty {
            folders = saved.map { URL(fileURLWithPath: $0) }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            folders = ["Desktop", "Downloads", "Documents", "Movies"].map { home.appendingPathComponent($0) }
        }
        overrides = Overrides.load(from: Overrides.defaultURL())
        watcher = FolderWatcher { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        watcher?.watch(folders)
        rescan()
    }

    // MARK: Scanning

    func rescan() {
        guard !isScanning else { rescanQueued = true; return }
        isScanning = true
        let roots = folders.map(\.path)
        let scanner = self.scanner
        let overrides = self.overrides
        scanner.excludedFolders = overrides.hiddenFolders
        let visual = self.visual
        Task.detached(priority: .utility) {
            let scan = scanner.scan(roots: roots.map { URL(fileURLWithPath: $0) })
            let result = Grouper.group(scan.files, roots: roots, hasher: scanner.contentHash, overrides: overrides)
            let catalog = Collector.collect(result, roots: roots, overrides: overrides)
            scanner.cache.save()
            await MainActor.run {
                self.apply(catalog, fileCount: scan.files.count)
                self.health = IndexHealth(lastScan: Date(), duration: scan.duration, files: scan.files.count,
                                          unreadable: scan.unreadable, codeProjects: scan.skippedCodeProjects,
                                          sequenceFiles: scan.skippedSequenceFiles,
                                          missingCorrections: self.missingCorrectionCount())
            }

            // Then gather stray projects and client fragments by how their artwork looks.
            // Fingerprints are cached, so after the first run this takes about a second.
            let matches = VisualMatcher.suggest(catalog, index: visual)
            guard !matches.isEmpty else { return }
            let refined = Collector.collect(result, roots: roots, overrides: overrides,
                                            suggestions: matches.map { [$0.orphanPath, $0.clientAnchorPath] })
            await MainActor.run { self.applyRefined(refined, fileCount: scan.files.count) }
        }
    }

    private func apply(_ catalog: Catalog, fileCount: Int) {
        let hiddenIDs = Set(catalog.hidden.flatMap { $0.projects.map(\.id) })
        projects = catalog.projects.filter { !hiddenIDs.contains($0.id) }
        collections = catalog.collections
        hiddenCollections = catalog.hidden
        standalone = catalog.standalone
        loose = catalog.loose
        var index: [String: CreativeFile] = [:]
        for p in catalog.projects { for f in p.files { index[f.file.path] = f.file } }
        for f in catalog.loose { index[f.path] = f }
        for c in catalog.collections + catalog.hidden { for f in c.singles { index[f.path] = f } }
        fileIndex = index
        self.fileCount = fileCount
        let firstScan = lastScan == nil
        lastScan = Date()
        isScanning = false
        notifyNewRecoveries(silently: firstScan && UserDefaults.standard.array(forKey: Self.knownRecoveredKey) == nil)
        if rescanQueued { rescanQueued = false; rescan() }
    }

    /// Second pass with visual matches: same data, only client membership changes.
    private func applyRefined(_ catalog: Catalog, fileCount: Int) {
        guard !isScanning else { return }   // a newer scan is running; it will refine itself
        withAnimation(Motion.standard) {
            collections = catalog.collections
            hiddenCollections = catalog.hidden
            standalone = catalog.standalone
        }
    }

    /// Corrections that point at files which no longer exist (moved or deleted outside Strata).
    private func missingCorrectionCount() -> Int {
        let o = overrides
        let paths = Set(o.links.flatMap { $0 } + o.clientLinks.flatMap { $0 } + o.detached + o.clientDetached
                        + Array(o.notes.keys) + Array(o.favorites))
        return paths.filter { !FileManager.default.fileExists(atPath: $0) }.count
    }

    // MARK: Lookup (ids are file paths, so a project is still found after its files change)

    func project(id: String) -> ProjectGroup? {
        projects.first { $0.id == id } ?? projects.first { $0.files.contains { $0.file.path == id } }
    }

    func collection(id: String) -> Client? {
        if let c = collections.first(where: { $0.id == id }) { return c }
        let path = id.replacingOccurrences(of: "collection:", with: "")
        return collections.first { c in c.projects.contains { $0.files.contains { $0.file.path == path } } || c.singles.contains { $0.path == path } }
    }

    func collection(containing projectID: String) -> Client? {
        collections.first { $0.projects.contains { $0.id == projectID } }
    }

    /// A scanned file, by path (for drag and drop from Finder or from Strata itself).
    func file(at path: String) -> CreativeFile? { fileIndex[(path as NSString).standardizingPath] }

    func projectCount(in folder: URL) -> Int {
        projects.filter { $0.files.contains { $0.file.path.hasPrefix(folder.path + "/") } }.count
    }

    // MARK: Watched folders

    func addFolder(_ url: URL) {
        guard !folders.contains(url) else { return }
        if Scanner.isSystemPath(url.path) {
            show("\(url.lastPathComponent) is a system folder: Strata only watches your work folders")
            return
        }
        setFolders(folders + [url])
    }

    func removeFolder(_ url: URL) { setFolders(folders.filter { $0 != url }) }

    private func setFolders(_ list: [URL]) {
        folders = list
        UserDefaults.standard.set(list.map(\.path), forKey: Self.foldersKey)
        watcher?.watch(list)
        rescan()
    }

    // MARK: Corrections

    private func correct(_ message: String? = nil, rescan needsRescan: Bool = true, _ change: (inout Overrides) -> Void) {
        undoStack.append(overrides)
        if undoStack.count > 50 { undoStack.removeFirst() }
        change(&overrides)
        overrides.save(to: Overrides.defaultURL())
        if let message { show(message, undo: true) }
        if needsRescan { rescan() }
    }

    // MARK: Undo

    /// Every correction (move, merge, rename, hide, favourite) can be undone, newest first.
    private var undoStack: [Overrides] = []
    var canUndo: Bool { !undoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        overrides = previous
        overrides.save(to: Overrides.defaultURL())
        show("Undone")
        rescan()
    }

    /// Puts `file` in the same project as `target` (any file of that project).
    func move(_ file: CreativeFile, toProjectOf target: ProjectGroup) {
        correct("Moved \(file.name) to \(target.name)") { o in
            o.detached.remove(file.path)
            o.links.removeAll { $0.contains(file.path) }
            o.links.append([file.path, target.first.file.path])
        }
    }

    /// Takes a file out of its project; it stays as a loose file until linked by hand.
    func detach(_ file: CreativeFile) {
        correct("Removed \(file.name) from its project") { o in
            o.links.removeAll { $0.contains(file.path) }
            o.detached.insert(file.path)
        }
    }

    func merge(_ a: ProjectGroup, into b: ProjectGroup) {
        correct("Merged \(a.name) into \(b.name)") { o in o.links.append([a.first.file.path, b.first.file.path]) }
    }

    func rename(_ project: ProjectGroup, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        correct { o in
            for f in project.files { o.projectNames.removeValue(forKey: f.file.path) }
            if !name.isEmpty { o.projectNames[project.first.file.path] = name }
        }
    }

    func rename(_ client: Client, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        correct { o in
            for f in client.allFiles { o.clientNames.removeValue(forKey: f.path) }
            if !name.isEmpty, let anchor = client.allFiles.min(by: { $0.modified < $1.modified }) { o.clientNames[anchor.path] = name }
        }
    }

    /// Moves a project (or a single file) into a client.
    func assign(_ file: CreativeFile, to client: Client) {
        guard let anchor = client.allFiles.first else { return }
        correct("Added to \(client.name)") { o in
            o.clientDetached.remove(file.path)
            o.clientLinks.removeAll { $0.first == file.path }
            o.clientLinks.append([file.path, anchor.path])
        }
    }

    func removeFromClient(_ project: ProjectGroup) {
        correct("Removed \(project.name) from its client") { o in
            for f in project.files { o.clientLinks.removeAll { $0.first == f.file.path } }
            o.clientDetached.insert(project.first.file.path)
        }
    }

    func mergeClients(_ a: Client, into b: Client) {
        guard let x = a.allFiles.first, let y = b.allFiles.first else { return }
        correct("Merged \(a.name) into \(b.name)") { o in o.clientLinks.append([x.path, y.path]) }
    }

    func hide(_ client: Client) {
        guard let anchor = client.allFiles.first else { return }
        correct("Hid \(client.name). Bring it back in Settings › Clients.") { o in o.hiddenClients.insert(anchor.path) }
    }

    func unhide(_ client: Client) {
        correct { o in for f in client.allFiles { o.hiddenClients.remove(f.path) } }
    }

    func hideFolder(_ path: String) {
        correct("Strata will skip \((path as NSString).lastPathComponent)") { o in
            if !o.hiddenFolders.contains(path) { o.hiddenFolders.append(path) }
        }
    }

    func unhideFolder(_ path: String) { correct { o in o.hiddenFolders.removeAll { $0 == path } } }

    func resetCorrections() { correct("All corrections cleared") { o in o = Overrides() } }

    // MARK: Favorites

    func isFavorite(_ project: ProjectGroup) -> Bool { project.files.contains { overrides.favorites.contains($0.file.path) } }
    func isFavorite(_ client: Client) -> Bool { client.allFiles.contains { overrides.favorites.contains($0.path) } }

    func toggleFavorite(_ project: ProjectGroup) {
        let on = isFavorite(project)
        correct(on ? "Removed \(project.name) from Favorites" : "Added \(project.name) to Favorites", rescan: false) { o in
            if on { for f in project.files { o.favorites.remove(f.file.path) } } else { o.favorites.insert(project.first.file.path) }
        }
    }

    func toggleFavorite(_ client: Client) {
        let on = isFavorite(client)
        guard let anchor = client.allFiles.min(by: { $0.modified < $1.modified }) else { return }
        correct(on ? "Removed \(client.name) from Favorites" : "Added \(client.name) to Favorites", rescan: false) { o in
            if on { for f in client.allFiles { o.favorites.remove(f.path) } } else { o.favorites.insert(anchor.path) }
        }
    }

    var favoriteClients: [Client] { collections.filter(isFavorite) }
    var favoriteProjects: [ProjectGroup] { projects.filter(isFavorite) }

    // MARK: Notes & status

    func note(for file: CreativeFile) -> String { overrides.notes[file.path] ?? "" }

    func setNote(_ text: String, for file: CreativeFile) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { overrides.notes.removeValue(forKey: file.path) } else { overrides.notes[file.path] = text }
        overrides.save(to: Overrides.defaultURL())
    }

    /// Writes the status as a Finder tag, so Finder and other apps see it too.
    func setStatus(_ status: VersionStatus?, for file: CreativeFile) {
        do {
            try FinderTags.set(status, on: file.path)
            show(status.map { "Marked \(file.name) as \($0.rawValue)" } ?? "Cleared status of \(file.name)")
        } catch {
            show("Couldn't tag \(file.name): \(error.localizedDescription)")
        }
        rescan()
    }

    // MARK: Tidy

    /// Moves files to the Trash (never deletes). Returns the bytes freed.
    @discardableResult
    func trash(_ files: [CreativeFile]) -> Int64 {
        var freed: Int64 = 0
        var failed = 0
        // Defence in depth: only files Strata scanned inside a watched folder can ever be trashed.
        let roots = folders.map { $0.standardizedFileURL.path + "/" }
        let allowed = files.filter { f in fileIndex[f.path] != nil && roots.contains { f.path.hasPrefix($0) } }
        failed += files.count - allowed.count
        for f in allowed {
            do {
                try FileManager.default.trashItem(at: f.url, resultingItemURL: nil)
                freed += f.size
            } catch { failed += 1 }
        }
        show("Moved \(files.count - failed) files to the Trash · \(Format.size(freed)) freed" + (failed > 0 ? " · \(failed) couldn't be moved" : ""))
        rescan()
        return freed
    }

    // MARK: Toasts & notifications

    func show(_ message: String, undo: Bool = false) {
        toastTask?.cancel()
        toastUndo = undo
        withAnimation(Motion.standard) { toast = message }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if !Task.isCancelled { withAnimation(Motion.effects) { toast = nil } }
        }
    }

    func copy(_ text: String, label: String? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("Copied \(label ?? text)")
    }

    /// Tells you when an app saved a "(Recovered)" file since the last scan, and which version came before it.
    private func notifyNewRecoveries(silently: Bool) {
        let known = Set(UserDefaults.standard.stringArray(forKey: Self.knownRecoveredKey) ?? [])
        let recovered = projects.flatMap { p in p.files.filter(\.isRecovered).map { (p, $0) } }
        let all = Set(recovered.map(\.1.file.path))
        UserDefaults.standard.set(Array(all), forKey: Self.knownRecoveredKey)
        guard !silently, Prefs.crashAlerts else { return }
        for (project, file) in recovered where !known.contains(file.file.path) {
            let before = project.versions.last { $0.file.modified < file.file.modified && !$0.isRecovered }
            let content = UNMutableNotificationContent()
            content.title = "\(project.name): file recovered after a crash"
            content.body = before.map { "Strata kept the version before it: \($0.file.name), saved \(Format.full.string(from: $0.file.modified))." }
                ?? "\(file.file.name) is now in the project's timeline."
            content.userInfo = ["project": project.id]
            let request = UNNotificationRequest(identifier: file.file.path, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

struct IndexHealth {
    var lastScan: Date?
    var duration: TimeInterval = 0
    var files = 0
    var unreadable: [String] = []
    var codeProjects = 0
    var sequenceFiles = 0
    var missingCorrections = 0
    var ok: Bool { unreadable.isEmpty }
}
