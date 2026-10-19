import SwiftUI
import StrataCore

/// The app's single source of truth: watched folders in, projects out. Rescans when the disk changes.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var projects: [ProjectGroup] = []
    @Published private(set) var loose: [CreativeFile] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var fileCount = 0
    @Published private(set) var folders: [URL]

    private let scanner = Scanner(cache: MetadataCache(fileURL: MetadataCache.defaultURL()))
    private var watcher: FolderWatcher?
    private var rescanQueued = false
    private static let foldersKey = "watchedFolders"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.foldersKey), !saved.isEmpty {
            folders = saved.map { URL(fileURLWithPath: $0) }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            folders = ["Desktop", "Downloads", "Documents", "Movies"].map { home.appendingPathComponent($0) }
        }
        watcher = FolderWatcher { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        watcher?.watch(folders)
        rescan()
    }

    func rescan() {
        guard !isScanning else { rescanQueued = true; return }
        isScanning = true
        let roots = folders
        let scanner = self.scanner
        Task.detached(priority: .utility) {
            let scan = scanner.scan(roots: roots)
            let result = Grouper.group(scan.files, roots: roots.map(\.path), hasher: scanner.contentHash)
            scanner.cache.save()
            await MainActor.run { self.apply(result, fileCount: scan.files.count) }
        }
    }

    private func apply(_ result: GroupingResult, fileCount: Int) {
        projects = result.projects
        loose = result.loose
        self.fileCount = fileCount
        lastScan = Date()
        isScanning = false
        if rescanQueued { rescanQueued = false; rescan() }
    }

    func addFolder(_ url: URL) {
        guard !folders.contains(url) else { return }
        setFolders(folders + [url])
    }

    func removeFolder(_ url: URL) { setFolders(folders.filter { $0 != url }) }

    private func setFolders(_ list: [URL]) {
        folders = list
        UserDefaults.standard.set(list.map(\.path), forKey: Self.foldersKey)
        watcher?.watch(list)
        rescan()
    }

    func project(id: String) -> ProjectGroup? { projects.first { $0.id == id } }

    func projectCount(in folder: URL) -> Int {
        projects.filter { $0.files.contains { $0.file.path.hasPrefix(folder.path + "/") } }.count
    }
}
