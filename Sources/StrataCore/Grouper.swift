import Foundation

/// Why a file was put into its project. Shown in the app as "Linked by".
public enum LinkReason: Int, Codable, Comparable, Sendable {
    case origin = 0          // first file of the project
    case similarName
    case sameName
    case identicalFile
    case sameOriginalDocument
    case exportedFrom
    case sameDocument
    case manual

    public static func < (a: LinkReason, b: LinkReason) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .origin: return "First file in this project"
        case .similarName: return "Similar file name"
        case .sameName: return "Same name, different version"
        case .identicalFile: return "Identical file contents"
        case .sameOriginalDocument: return "Same Adobe document (Save As / recovered)"
        case .exportedFrom: return "Exported from a file in this project"
        case .sameDocument: return "Same Adobe Document ID"
        case .manual: return "Added by you"
        }
    }
}

public struct ProjectFile: Identifiable, Hashable, Sendable {
    public var id: String { file.path }
    public let file: CreativeFile
    public var reason: LinkReason
    /// An output (PDF, PNG, MP4…) hanging off a source file in the same project.
    public var isExport: Bool
    /// Path of the source file this export belongs to.
    public var exportOf: String?
    public var duplicateOf: String?
    public var isRecovered: Bool { file.isRecovered }
    public var isDuplicate: Bool { duplicateOf != nil }
}

public struct ProjectGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Every file, oldest first.
    public let files: [ProjectFile]

    /// The main line of the timeline: working files (or everything, if the project has no working files).
    public var versions: [ProjectFile] { files.filter { !$0.isExport } }
    public func exports(of version: ProjectFile) -> [ProjectFile] { files.filter { $0.exportOf == version.file.path } }

    public var first: ProjectFile { files[0] }
    public var latest: ProjectFile { versions.last ?? files[files.count - 1] }
    public var lastModified: Date { files.map(\.file.modified).max() ?? .distantPast }
    public var kinds: [FileKind] {
        var out: [FileKind] = []
        for f in files where !out.contains(f.file.kind) { out.append(f.file.kind) }
        return out
    }
    public var extensions: [String] {
        var out: [String] = []
        for f in files where !out.contains(f.file.fileExtension) { out.append(f.file.fileExtension) }
        return out
    }
    public var hasRecovered: Bool { files.contains { $0.isRecovered } }
    public var duplicateCount: Int { files.filter(\.isDuplicate).count }
    public var needsReview: Bool { hasRecovered || duplicateCount > 0 }
    public var isVideo: Bool { files.contains { $0.file.kind.isVideoFamily } }
}

public struct GroupingResult: Sendable {
    public let projects: [ProjectGroup]   // 2+ files, most recently touched first
    public let loose: [CreativeFile]      // files that matched nothing
}

/// Decides which files belong together.
public enum Grouper {
    /// A specifically named export may join its only source without a name match if saved this close to it.
    static let idTimeWindow: TimeInterval = 3 * 24 * 3600

    /// A file name found in this many folders is treated as a naming convention.
    static let structuralFolderCount = 3

    /// Specific words of the nearest parent folder (below the scanned roots) that names something,
    /// skipping organiser folders like "2_Photos" and folders that just repeat the file's own name.
    static func context(of path: String, roots: [String], nameTokens: [String]) -> String? {
        var dir = (path as NSString).deletingLastPathComponent
        let stops = Set(roots.map { ($0 as NSString).standardizingPath } + [NSHomeDirectory(), "/"])
        while !stops.contains(dir) && dir.count > 1 {
            let words = NameNormalizer.folderTokens(for: (dir as NSString).lastPathComponent)
            if !words.isEmpty && !Set(words).isSubset(of: nameTokens) { return words.sorted().joined(separator: " ") }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    public static func defaultRoots() -> [String] {
        ["Desktop", "Downloads", "Documents", "Movies", "Pictures"].map { NSHomeDirectory() + "/" + $0 }
    }

    public static func group(_ files: [CreativeFile], roots: [String] = defaultRoots(),
                             hasher: ((CreativeFile) -> String?)? = nil,
                             overrides: Overrides = Overrides()) -> GroupingResult {
        let n = files.count
        guard n > 0 else { return GroupingResult(projects: [], loose: []) }
        var uf = UnionFind(n)
        var reason = [LinkReason](repeating: .origin, count: n)
        let detached = Set(files.indices.filter { overrides.detached.contains(files[$0].path) })
        func link(_ a: Int, _ b: Int, _ r: LinkReason) {
            guard a != b else { return }
            if r != .manual && (detached.contains(a) || detached.contains(b)) { return }
            uf.union(a, b)
            reason[a] = max(reason[a], r)
            reason[b] = max(reason[b], r)
        }

        let tokens = files.map { NameNormalizer.tokens(for: $0.name) }
        let keys = files.map { NameNormalizer.key(for: $0.name) }

        // Adobe IDs prove two files share history, not that they are the same job: designers often
        // Save As (or duplicate in Finder) the current file to start the next one. So an ID link also
        // needs related names. Crash recoveries keep their name; generically named files
        // ("Untitled-3 (Recovered).ai", "export-01.png") attach to their nearest named sibling.
        func gap(_ a: Int, _ b: Int) -> TimeInterval { abs(files[a].modified.timeIntervalSince(files[b].modified)) }
        func linkRelated(_ members: [Int], _ r: LinkReason, minSimilarity: Double) {
            guard members.count > 1, members.count <= 400 else { return }
            var matched = Set<Int>()
            let named = members.filter { keys[$0] != nil }
            for x in 0..<named.count {
                for y in (x + 1)..<named.count where NameNormalizer.similarity(tokens[named[x]], tokens[named[y]]) >= minSimilarity {
                    link(named[x], named[y], r)
                    matched.formUnion([named[x], named[y]])
                }
            }
            // Generic or unmatched names attach to the one file saved closest in time, so they can
            // never glue two different jobs together.
            for i in members where !matched.contains(i) {
                guard let nearest = named.filter({ $0 != i }).min(by: { gap(i, $0) < gap(i, $1) }) else { continue }
                if keys[i] == nil || files[i].isRecovered { link(i, nearest, r) }
            }
        }

        // 1. Same DocumentID: copies, renames and crash recoveries of one document.
        var byDoc: [String: [Int]] = [:]
        for (i, f) in files.enumerated() { if let id = f.xmp?.documentID { byDoc[id, default: []].append(i) } }
        for (_, m) in byDoc { linkRelated(m, .sameDocument, minSimilarity: 0.34) }

        // 2. Same OriginalDocumentID: the whole Save As family. Weaker, so names must agree more.
        var byOriginal: [String: [Int]] = [:]
        for (i, f) in files.enumerated() { if let id = f.xmp?.originalDocumentID { byOriginal[id, default: []].append(i) } }
        for (_, m) in byOriginal { linkRelated(m, .sameOriginalDocument, minSimilarity: 0.5) }

        // 3. DerivedFrom points at the exact document a file was saved or exported from.
        //    Exports (PDF, PNG…) attach to that source; Save As copies follow the rules above.
        var byDocID: [String: [Int]] = [:]
        for (i, f) in files.enumerated() { if let id = f.xmp?.documentID { byDocID[id, default: []].append(i) } }
        for (i, f) in files.enumerated() {
            for id in f.xmp?.derivedFromIDs ?? [] {
                guard let candidates = byDocID[id]?.filter({ $0 != i }), !candidates.isEmpty else { continue }
                if f.kind.isSource {
                    let similar = candidates.filter { NameNormalizer.similarity(tokens[$0], tokens[i]) >= 0.5 }
                    if !similar.isEmpty { similar.forEach { link($0, i, .exportedFrom) }; continue }
                    if keys[i] == nil, let nearest = candidates.min(by: { gap(i, $0) < gap(i, $1) }) { link(nearest, i, .exportedFrom) }
                } else {
                    // One source only. A specifically named export ("Velora Logo.png") must look like its
                    // source, since the source may itself be a renamed duplicate of another job's file.
                    var pool = candidates
                    if keys[i] != nil {
                        let similar = candidates.filter { keys[$0] == nil || NameNormalizer.similarity(tokens[$0], tokens[i]) >= 0.34 }
                        if !similar.isEmpty { pool = similar }
                        else if candidates.count == 1, gap(i, candidates[0]) < idTimeWindow { pool = candidates }
                        else { continue }
                    }
                    let before = pool.filter { files[$0].modified <= f.modified.addingTimeInterval(60) }
                    let pick = (before.isEmpty ? pool : before).max { files[$0].modified < files[$1].modified }!
                    link(pick, i, .exportedFrom)
                }
            }
        }

        // 4. Same normalized name ("atlas_logo_final.ai" == "Atlas Logo (Recovered) 2.ai" == "atlas-logo.pdf").
        //    When one name repeats across many folders ("01_Market/photos/room.jpg", "02_Swim/photos/room.jpg")
        //    it's a naming convention, not one project: split those by their nearest named parent folder.
        var byKey: [String: [Int]] = [:]
        for (i, k) in keys.enumerated() { if let k { byKey[k, default: []].append(i) } }
        var structuralKeys = Set<String>()
        for (k, m) in byKey where m.count > 1 {
            let folders = Set(m.map { files[$0].folder })
            guard folders.count >= structuralFolderCount else {
                for i in m.dropFirst() { link(m[0], i, .sameName) }
                continue
            }
            structuralKeys.insert(k)
            var byContext: [String: [Int]] = [:]
            var noContext: [Int] = []
            for i in m {
                if let c = context(of: files[i].path, roots: roots, nameTokens: tokens[i]) { byContext[c, default: []].append(i) }
                else { noContext.append(i) }
            }
            for (_, g) in byContext { for i in g.dropFirst() { link(g[0], i, .sameName) } }
            if byContext.count <= 1 {
                let all = (byContext.values.first ?? []) + noContext
                for i in all.dropFirst() { link(all[0], i, .sameName) }
            }
        }

        // 5. Name is the same plus one extra word ("atlas logo" vs "atlas logo sketch"), only when that
        //    shorter name has a single possible match, so different projects don't chain together.
        //    A one-word name only links when the extra word is generic ("atlas" -> "atlas logo").
        var supersets: [String: [(key: String, extra: String)]] = [:]
        for k in byKey.keys {
            let words = k.split(separator: " ").map(String.init)
            guard words.count >= 2 else { continue }
            for (i, extra) in words.enumerated() {
                var rest = words; rest.remove(at: i)
                let sub = rest.joined(separator: " ")
                if byKey[sub] != nil { supersets[sub, default: []].append((k, extra)) }
            }
        }
        var subsetCount: [String: Int] = [:]
        for (_, sups) in supersets { for s in sups { subsetCount[s.key, default: 0] += 1 } }
        for (sub, sups) in supersets where sups.count == 1 && subsetCount[sups[0].key] == 1 {
            if structuralKeys.contains(sub) || structuralKeys.contains(sups[0].key) { continue }
            let single = !sub.contains(" ")
            if single && !NameNormalizer.weak.contains(sups[0].extra) { continue }
            if let a = byKey[sub]?.first, let b = byKey[sups[0].key]?.first { link(a, b, .similarName) }
        }

        // 6. The designer's own corrections.
        var indexOf: [String: Int] = [:]
        for (i, f) in files.enumerated() { indexOf[f.path] = i }
        for pair in overrides.links where pair.count == 2 {
            if let a = indexOf[pair[0]], let b = indexOf[pair[1]] { link(a, b, .manual) }
        }

        // Collect components.
        var components: [Int: [Int]] = [:]
        for i in 0..<n { components[uf.find(i), default: []].append(i) }

        var projects: [ProjectGroup] = []
        var loose: [CreativeFile] = []
        for (_, members) in components {
            if members.count == 1 { loose.append(files[members[0]]); continue }
            projects.append(buildProject(members: members, files: files, tokens: tokens, reasons: reason, hasher: hasher,
                                         names: overrides.projectNames))
        }
        projects.sort { $0.lastModified > $1.lastModified }
        loose.sort { $0.modified > $1.modified }
        return GroupingResult(projects: projects, loose: loose)
    }

    static func buildProject(members: [Int], files: [CreativeFile], tokens: [[String]], reasons: [LinkReason],
                             hasher: ((CreativeFile) -> String?)?, names: [String: String] = [:]) -> ProjectGroup {
        let sorted = members.sorted { files[$0].modified < files[$1].modified }
        let hasSource = sorted.contains { files[$0].kind.isSource }

        var out: [ProjectFile] = sorted.map {
            ProjectFile(file: files[$0], reason: reasons[$0], isExport: hasSource && !files[$0].kind.isSource,
                        exportOf: nil, duplicateOf: nil)
        }
        out[0].reason = .origin

        // Attach each export to its source: by DerivedFrom ID, else the latest source saved before it.
        let sources = out.indices.filter { !out[$0].isExport }
        for i in out.indices where out[i].isExport {
            let derived = Set(out[i].file.xmp?.derivedFromIDs ?? []).union([out[i].file.xmp?.documentID].compactMap { $0 })
            let byID = sources.last { s in
                let x = out[s].file.xmp
                return [x?.documentID, x?.originalDocumentID].compactMap { $0 }.contains(where: derived.contains)
            }
            let byTime = sources.last { out[$0].file.modified <= out[i].file.modified.addingTimeInterval(60) }
            out[i].exportOf = out[byID ?? byTime ?? sources[0]].file.path
        }

        // Exact duplicates: same size, then same content hash.
        if let hasher {
            var bySize: [Int64: [Int]] = [:]
            for (i, f) in out.enumerated() { bySize[f.file.size, default: []].append(i) }
            for (_, idx) in bySize where idx.count > 1 {
                var firstWithHash: [String: Int] = [:]
                for i in idx {
                    guard let h = hasher(out[i].file) else { continue }
                    if let original = firstWithHash[h] {
                        out[i].duplicateOf = out[original].file.path
                        out[i].reason = max(out[i].reason, .identicalFile)
                    } else { firstWithHash[h] = i }
                }
            }
        }

        // Name: the most common word set among working files, in its original word order.
        var counts: [[String]: Int] = [:]
        for pool in [sources, Array(out.indices)] where counts.isEmpty {
            for i in pool {
                let t = tokens[sorted[i]]
                if !NameNormalizer.strongTokens(t).isEmpty { counts[t, default: 0] += 1 }
            }
        }
        let best = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key.count > b.key.count }?.key
        let custom = out.lazy.compactMap { names[$0.file.path] }.first
        let name = custom ?? best.map(NameNormalizer.displayName) ?? out[0].file.baseName

        return ProjectGroup(id: out[0].file.path, name: name, files: out)
    }
}

struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]
    init(_ n: Int) { parent = Array(0..<n); rank = Array(repeating: 0, count: n) }
    mutating func find(_ x: Int) -> Int {
        var r = x
        while parent[r] != r { r = parent[r] }
        var c = x
        while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
        return r
    }
    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return }
        if rank[ra] < rank[rb] { parent[ra] = rb } else if rank[ra] > rank[rb] { parent[rb] = ra } else { parent[rb] = ra; rank[ra] += 1 }
    }
}
