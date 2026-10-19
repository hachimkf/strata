import Foundation
import CryptoKit

/// Remembers what we already read from each file so rescans only touch new or changed files.
public final class MetadataCache: @unchecked Sendable {
    struct Entry: Codable {
        var size: Int64
        var modified: Date
        var xmp: XMPInfo?
        var xmpRead: Bool
        var hash: String?
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()
    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Strata", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("metadata-cache-v3.json")   // bump when XMPInfo parsing changes
    }

    func entry(for path: String, size: Int64, modified: Date) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[path], e.size == size, abs(e.modified.timeIntervalSince(modified)) < 1 else { return nil }
        return e
    }

    func store(_ entry: Entry, for path: String) {
        lock.lock(); entries[path] = entry; lock.unlock()
    }

    func setHash(_ hash: String, for path: String) {
        lock.lock(); entries[path]?.hash = hash; lock.unlock()
    }

    /// Drops entries for files that no longer exist under the scanned roots.
    func prune(keeping paths: Set<String>) {
        lock.lock(); entries = entries.filter { paths.contains($0.key) }; lock.unlock()
    }

    public func save() {
        guard let fileURL else { return }
        lock.lock(); let snapshot = entries; lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) { SecureStore.write(data, to: fileURL) }
    }
}

public struct ScanResult: Sendable {
    public let files: [CreativeFile]
    public let duration: TimeInterval
    public let xmpReads: Int
    /// Folders macOS wouldn't let Strata read (privacy permission, damaged folder…).
    public var unreadable: [String] = []
    public var skippedCodeProjects = 0
    public var skippedSequenceFiles = 0
}

/// Walks folders and collects creative files with their metadata. Never writes to scanned folders.
public final class Scanner: @unchecked Sendable {
    public let cache: MetadataCache
    public var minimumFileSize: Int64 = 1024
    /// Folders (and everything inside) that are never scanned.
    public var excludedFolders: [String] = []

    /// A folder containing one of these is a code project (an app's own image assets aren't design work).
    static let codeProjectMarkers = [
        ".git", "package.json", "Package.swift", "Podfile", "build.gradle", "settings.gradle", "pubspec.yaml",
        "Cargo.toml", "go.mod", "pyproject.toml", "requirements.txt", "Gemfile", "composer.json", "CMakeLists.txt",
        "project.yml", ".xcodeproj", "AndroidManifest.xml",
    ]

    static let skippedFolderNames: Set<String> = [
        "node_modules", ".git", "Library", "Caches", "DerivedData", "Pods", ".Trash", "venv", ".venv",
        "__pycache__", "build", "dist", ".build", "Adobe Premiere Pro Auto-Save", "Media Cache Files",
        "Media Cache", "Peak Files", "Adobe After Effects Auto-Save",
        // App data that lives in Documents but isn't anyone's design work.
        "SoftMaker", "Microsoft User Data", "Zoom", "WhatsApp", "Steam", "Unity", "Blackmagic Design",
        "Native Instruments", "Logic", "GarageBand", "iMovie Library", "Final Cut Backups",
    ]

    static func isCodeProject(_ dir: URL) -> Bool {
        let fm = FileManager.default
        if codeProjectMarkers.contains(where: { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }) { return true }
        // Xcode projects are folders named *.xcodeproj
        let items = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return items.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    /// Folders of rendered frames ("frame-0001.png" … "frame-0240.png"): one image sequence, not design files.
    static func renderSequenceFolders(_ found: [(URL, FileKind, Int64, Date, Date, [String])]) -> Set<String> {
        var byFolder: [String: [String]] = [:]
        for (url, kind, _, _, _, _) in found where kind == .image {
            byFolder[url.deletingLastPathComponent().path, default: []].append(url.lastPathComponent.lowercased())
        }
        var out = Set<String>()
        for (folder, names) in byFolder where names.count >= 24 {
            var stems: [String: Int] = [:]
            for n in names {
                let stem = n.replacingOccurrences(of: "[0-9]+", with: "#", options: .regularExpression)
                stems[stem, default: 0] += 1
            }
            if let top = stems.values.max(), Double(top) / Double(names.count) >= 0.8 { out.insert(folder) }
        }
        return out
    }

    public init(cache: MetadataCache) { self.cache = cache }

    public func scan(roots: [URL]) -> ScanResult {
        let started = Date()
        var found: [(URL, FileKind, Int64, Date, Date, [String])] = []
        let excluded = excludedFolders.map { ($0 as NSString).standardizingPath }
        var seen = Set<String>()
        let unreadable = PathList()
        var codeProjects = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey]

        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in unreadable.add(url.path); return true }) else {
                unreadable.add(root.path)
                continue
            }
            for case let url as URL in walker {
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isDirectory == true {
                    if Self.skippedFolderNames.contains(url.lastPathComponent) || excluded.contains(url.standardizedFileURL.path)
                        || Self.isCodeProject(url) {
                        if Self.isCodeProject(url) { codeProjects += 1 }
                        walker.skipDescendants()
                    }
                    continue
                }
                guard v.isRegularFile == true, let kind = FileKind.from(extension: url.pathExtension) else { continue }
                let size = Int64(v.fileSize ?? 0)
                guard size >= minimumFileSize else { continue }
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                let modified = v.contentModificationDate ?? Date.distantPast
                found.append((url, kind, size, v.creationDate ?? modified, modified, v.tagNames ?? []))
            }
        }

        // Drop render sequences.
        let sequences = Self.renderSequenceFolders(found)
        let beforeSequences = found.count
        if !sequences.isEmpty {
            found.removeAll { item in item.1 == .image && sequences.contains(item.0.deletingLastPathComponent().path) }
            seen = Set(found.map { $0.0.standardizedFileURL.path })
        }

        // Read XMP for new / changed files in parallel.
        var files = [CreativeFile?](repeating: nil, count: found.count)
        let reads = AtomicCounter()
        files.withUnsafeMutableBufferPointer { buffer in
            let out = buffer
            DispatchQueue.concurrentPerform(iterations: found.count) { i in
                let (url, kind, size, created, modified, tags) = found[i]
                let path = url.standardizedFileURL.path
                var file = CreativeFile(path: path, kind: kind, size: size, created: created, modified: modified, tags: tags)
                if let cached = cache.entry(for: path, size: size, modified: modified), cached.xmpRead || !kind.mayContainXMP {
                    file.xmp = cached.xmp
                    file.contentHash = cached.hash
                } else {
                    file.xmp = kind.mayContainXMP ? XMPReader.read(url: url) : nil
                    reads.increment()
                    cache.store(.init(size: size, modified: modified, xmp: file.xmp, xmpRead: true, hash: nil), for: path)
                }
                out[i] = file
            }
        }
        cache.prune(keeping: seen)
        cache.save()
        return ScanResult(files: files.compactMap { $0 }, duration: Date().timeIntervalSince(started), xmpReads: reads.value,
                          unreadable: unreadable.items, skippedCodeProjects: codeProjects,
                          skippedSequenceFiles: beforeSequences - found.count)
    }

    /// SHA-256 of the file contents, cached. Only used to confirm exact duplicates of equal size.
    public func contentHash(for file: CreativeFile) -> String? {
        if let h = file.contentHash { return h }
        guard let handle = try? FileHandle(forReadingFrom: file.url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        cache.setHash(hash, for: file.path)
        return hash
    }
}

final class AtomicCounter: @unchecked Sendable {
    private var n = 0
    private let lock = NSLock()
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

final class PathList: @unchecked Sendable {
    private var list: [String] = []
    private let lock = NSLock()
    func add(_ p: String) { lock.lock(); if !list.contains(p) && list.count < 200 { list.append(p) }; lock.unlock() }
    var items: [String] { lock.lock(); defer { lock.unlock() }; return list }
}
