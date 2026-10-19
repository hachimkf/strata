import Foundation

/// A client or brand: every project and stray file that belongs to it ("Norvia", "Velora Coffee").
public struct Collection: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Projects with versions, most recently saved first.
    public let projects: [ProjectGroup]
    /// Files that belong to this client but have no other version.
    public let singles: [CreativeFile]

    public var allFiles: [CreativeFile] { projects.flatMap { $0.files.map(\.file) } + singles }
    public var fileCount: Int { projects.reduce(0) { $0 + $1.files.count } + singles.count }
    public var lastModified: Date { allFiles.map(\.modified).max() ?? .distantPast }
    public var firstModified: Date { allFiles.map(\.modified).min() ?? .distantPast }
    /// Newest files first, for covers and thumbnails.
    public var recentFiles: [CreativeFile] { allFiles.sorted { $0.modified > $1.modified } }
    public var latest: CreativeFile? { recentFiles.first }
    public var hasRecovered: Bool { projects.contains(where: \.hasRecovered) }
    public var extensions: [String] {
        var out: [String] = []
        for f in allFiles.sorted(by: { $0.modified > $1.modified }) where !out.contains(f.fileExtension) { out.append(f.fileExtension) }
        return out
    }
}

public struct Catalog: Sendable {
    public let collections: [Collection]   // 2+ projects or files, most recent first
    public let hidden: [Collection]        // clients the designer hid
    public let projects: [ProjectGroup]    // every project, inside a collection or not
    public let standalone: [ProjectGroup]  // projects that belong to no collection
    public let loose: [CreativeFile]       // files that matched nothing at all

    public func collection(containing projectID: String) -> Collection? {
        collections.first { $0.projects.contains { $0.id == projectID } }
    }
}

/// Gathers projects and loose files into clients / brands.
public enum Collector {
    /// Folder words that organise but never name a client.
    static let organiserWords: Set<String> = [
        "organized", "organised", "by", "month", "months", "week", "year", "same", "name", "names",
        "new", "folder", "untitled", "copy", "misc", "various", "divers", "autres", "other", "others",
        "freelance", "personal", "perso", "clients", "client", "work", "projects", "projets",
        "settings", "adobe", "softmaker", "microsoft", "zoom", "screenshots", "captures", "inbox",
        "chatgpt", "chat", "gpt", "codex", "claude", "cursor", "temp", "tmp", "cache", "backup", "backups",
    ]

    /// Common design deliverables: they start many file names but never identify a client.
    static let deliverableWords: Set<String> = [
        "etude", "cas", "case", "study", "menu", "carte", "visite", "business", "flyer", "affiche",
        "brochure", "catalogue", "catalog", "packaging", "pack", "box", "label", "etiquette", "sticker",
        "stickers", "tshirt", "shirt", "mug", "presentation", "prez", "deck", "report", "rapport", "cv",
        "resume", "facture", "invoice", "devis", "quote", "contrat", "contract", "stand", "kit", "signage",
        "habillage", "roll", "rollup", "kakemono", "badge", "invitation", "certificate", "certificat",
        "bdc", "bon", "commande", "planning", "calendar", "calendrier", "agenda", "newsletter", "email",
        "signature", "header", "footer", "slide", "slides", "thumbnail", "sizes", "size", "room", "detail",
        "collection", "included", "whats", "hidden", "find", "gradient", "background", "splash", "mockups",
        "icon", "icons", "speaker", "company", "best", "brand", "book", "guide", "guidelines", "charte",
        "graphique", "identity", "identite", "visual", "visuel", "visuels", "photo", "photos", "image",
        "images", "print", "web", "social", "media", "post", "posts", "story", "stories", "reel", "carousel",
        "carrousel", "banner", "banners", "cover", "covers", "frame", "test", "sample", "exemple", "example",
    ]

    /// Everyday words (mostly French, Spanish, Italian) that aren't in the English word list but are never brands.
    static let commonWords: Set<String> = [
        "cafe", "caffe", "coffe", "boulangerie", "patisserie", "restaurant", "resto", "hotel", "maison", "jardin",
        "cuisine", "plage", "soleil", "mer", "ville", "salon", "maires", "voeux", "fete", "noel", "ramadan", "aid",
        "eid", "mariage", "anniversaire", "affiche", "carte", "cartes", "logo", "marque", "nouveau", "nouvelle",
        "grand", "petit", "rouge", "bleu", "vert", "jaune", "noir", "blanc", "rose", "gris", "orange", "violet",
        "azul", "rojo", "verde", "negro", "blanco", "rosso", "nero", "bianco", "casa", "bella", "dolce", "mercado",
        "souk", "medina", "riad", "dar", "beldi", "atlas", "sahara", "maroc", "morocco", "marrakech", "casablanca",
        "rabat", "tanger", "fes", "agadir", "paris", "france", "dubai", "london", "madrid", "milano",
        "insta", "linkedin", "tiktok", "youtube", "facebook", "pinterest", "etsy", "shopify", "amazon",
        "mockup", "mockups", "freepik", "envato", "upscaled", "upscale", "topaz", "gigapixel", "codex", "chatgpt",
        "concat", "render", "renders", "output", "scene", "scenes", "comment", "comments", "speakers", "items",
    ]

    /// A unit is something to place in a collection: a whole project, or one loose file.
    struct Unit {
        let project: ProjectGroup?
        let file: CreativeFile?
        var files: [CreativeFile] { project.map { $0.files.map(\.file) } ?? [file!] }
        let nameTokens: [String]
    }

    /// A client with fewer files than this can be absorbed by a bigger one (fragments like "Kiosk", "Front").
    public static let smallClientFiles = 25

    /// - Parameter suggestions: pairs (file of a small group, file of a big client) from visual matching.
    public static func collect(_ grouping: GroupingResult, roots: [String] = Grouper.defaultRoots(),
                               overrides: Overrides = Overrides(), suggestions: [[String]] = []) -> Catalog {
        var units: [Unit] = grouping.projects.map {
            Unit(project: $0, file: nil, nameTokens: NameNormalizer.tokens(for: $0.name + ".x"))
        }
        units += grouping.loose.map { Unit(project: nil, file: $0, nameTokens: NameNormalizer.tokens(for: $0.name)) }
        let n = units.count
        var uf = UnionFind(n)
        var edgeLog: [String] = []
        #if DEBUG
        let tracing = ProcessInfo.processInfo.environment["STRATA_EDGES"] != nil
        #else
        let tracing = false
        #endif
        func label(_ i: Int) -> String { units[i].project.map { "P:" + $0.name } ?? ("F:" + units[i].files[0].path) }
        var unitOf: [String: Int] = [:]
        for (i, u) in units.enumerated() { for f in u.files { unitOf[f.path] = i } }
        let kept = Set(overrides.clientDetached.compactMap { unitOf[$0] })
        func join(_ a: Int, _ b: Int, _ why: String) {
            if why != "manual" && (kept.contains(a) || kept.contains(b)) { return }
            if tracing { edgeLog.append("\(why)\t\(label(a))\t\(label(b))") }
            uf.union(a, b)
        }
        let rootSet = roots.map { ($0 as NSString).standardizingPath }

        #if DEBUG
        let signals = Set((ProcessInfo.processInfo.environment["STRATA_SIGNALS"] ?? "adobe,folder,brand").split(separator: ",").map(String.init))
        #else
        let signals: Set<String> = ["adobe", "folder", "brand"]
        #endif

        // 2. Client folders: the first meaningfully named folder under a watched root.
        var anchorOf = [Set<String>](repeating: [], count: n)
        for (i, u) in units.enumerated() {
            for f in u.files { if let a = anchor(for: f.path, roots: rootSet, depth: 0) { anchorOf[i].insert(a) } }
        }
        // A folder holding lots of clients ("Freelance") is split one level deeper.
        var byAnchor: [String: Set<Int>] = [:]
        for (i, set) in anchorOf.enumerated() { for a in set { byAnchor[a, default: []].insert(i) } }
        for (a, members) in byAnchor where members.count > 80 {
            for i in members {
                anchorOf[i].remove(a)
                for f in units[i].files where f.path.hasPrefix(a + "/") {
                    if let deeper = anchor(for: f.path, roots: [a], depth: 0) { anchorOf[i].insert(deeper) }
                }
            }
        }
        // One client folder per project: where most of its files are (ties: the newest file's folder),
        // so a project copied into two clients' folders can't weld them together.
        for i in 0..<n where anchorOf[i].count > 1 {
            var count: [String: Int] = [:]
            var newest: [String: Date] = [:]
            for f in units[i].files {
                guard let a = anchorOf[i].first(where: { f.path.hasPrefix($0 + "/") }) else { continue }
                count[a, default: 0] += 1
                newest[a] = max(newest[a] ?? .distantPast, f.modified)
            }
            if let best = count.max(by: { x, y in
                x.value != y.value ? x.value < y.value : (newest[x.key] ?? .distantPast) < (newest[y.key] ?? .distantPast)
            })?.key {
                anchorOf[i] = [best]
            }
        }
        byAnchor = [:]
        for (i, set) in anchorOf.enumerated() { for a in set { byAnchor[a, default: []].insert(i) } }
        for (a, members) in byAnchor where signals.contains("folder") && members.count > 1 {
            let m = Array(members)
            for i in m.dropFirst() { join(m[0], i, "folder:" + a) }
        }

        // 3. Brand words: a specific word that *starts* names in several places ("Norvia …", "Velora …").
        //    Each name joins one brand only (its first brand word), so a file mentioning two
        //    clients can't weld them together.
        var leading: [String: Int] = [:]
        for u in units { if let first = brandCandidates(u.nameTokens).first { leading[first, default: 0] += 1 } }
        let brands = Set(leading.filter { word, count in
            if Dictionary.contains(word) || commonWords.contains(word) { return false }   // "left", "grid", "cafe"
            if Dictionary.isPlural(word) { return count >= 4 }            // "norvia" yes, "frames" rarely
            return count >= (word.count <= 4 ? 3 : 2)                     // short words need more evidence
        }.keys)
        // Spelling variants of one brand ("solarastudio", "solara") share their first 6 letters.
        var canonical: [String: String] = [:]
        for b in brands.sorted(by: { (leading[$0] ?? 0) > (leading[$1] ?? 0) }) {
            canonical[b] = canonical.values.first { $0.prefix(6) == b.prefix(6) && b.count >= 6 && $0.count >= 6 } ?? b
        }
        func brand(in tokens: [String]) -> String? {
            brandCandidates(tokens).filter(brands.contains).max { (leading[$0] ?? 0) < (leading[$1] ?? 0) }.flatMap { canonical[$0] }
        }
        var byBrand: [String: [Int]] = [:]
        var brandOf = [String?](repeating: nil, count: n)
        for (i, u) in units.enumerated() {
            if let b = brand(in: u.nameTokens) {
                byBrand[b, default: []].append(i)
                brandOf[i] = b
            }
        }
        for (b, m) in byBrand where signals.contains("brand") && m.count > 1 {
            for i in m.dropFirst() { join(m[0], i, "brand:" + b) }
        }
        // A client folder named after a brand belongs to that brand ("Daily Crediting Norvia" → Norvia).
        for (a, members) in byAnchor where signals.contains("brand") {
            let words = NameNormalizer.tokens(for: (a as NSString).lastPathComponent + ".x")
            if let b = brand(in: words), let target = byBrand[b]?.first, let first = members.first {
                join(target, first, "folder-brand:" + b)
            }
        }
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["STRATA_EDGES"] {
            try? edgeLog.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        #endif

        // 4. Adobe families adopt files with no client of their own (no client folder, no brand word).
        //    They never merge two identified clients: designers often start one client's file from another's.
        var identified = [Bool](repeating: false, count: n)
        for i in 0..<n { identified[i] = !anchorOf[i].isEmpty || brandOf[i] != nil }
        var byID: [String: Set<Int>] = [:]
        for (i, u) in units.enumerated() {
            for f in u.files {
                guard let x = f.xmp else { continue }
                for id in [x.documentID, x.originalDocumentID].compactMap({ $0 }) + x.derivedFromIDs { byID[id, default: []].insert(i) }
            }
        }
        func when(_ i: Int) -> Date { units[i].files.map(\.modified).max() ?? .distantPast }
        for (_, members) in byID where signals.contains("adobe") && members.count > 1 && members.count <= 40 {
            let owners = members.filter { identified[$0] }
            let orphans = members.filter { !identified[$0] }
            for o in orphans {
                if let home = owners.min(by: { abs(when($0).timeIntervalSince(when(o))) < abs(when($1).timeIntervalSince(when(o))) }) {
                    join(home, o, "adobe")
                } else if let other = orphans.first, other != o {
                    join(other, o, "adobe")
                }
            }
        }

        // 5. Small groups join the one big client they share a signature word or the look with.
        func components() -> [Int: [Int]] {
            var c: [Int: [Int]] = [:]
            for i in 0..<n { c[uf.find(i), default: []].append(i) }
            return c
        }
        func fileCount(_ members: [Int]) -> Int { members.reduce(0) { $0 + units[$1].files.count } }
        var comps = components()
        let big = comps.filter { fileCount($0.value) >= smallClientFiles }
        // Signature words: used by 3+ projects of exactly one big client, and by no other big client.
        var owners: [String: [Int: Int]] = [:]
        for (root, members) in big {
            for i in members {
                for w in Set(NameNormalizer.strongTokens(units[i].nameTokens)) where !deliverableWords.contains(w) && w.count >= 3 {
                    owners[w, default: [:]][root, default: 0] += 1
                }
            }
        }
        var signature: [String: Int] = [:]
        for (w, byRoot) in owners where byRoot.count == 1 {
            if let (root, count) = byRoot.first, count >= 3 { signature[w] = root }
        }
        if signals.contains("brand") {
            for (root, members) in comps where big[root] == nil {
                var votes: [Int: Int] = [:]
                for i in members {
                    for w in Set(NameNormalizer.strongTokens(units[i].nameTokens)) { if let r = signature[w] { votes[r, default: 0] += 1 } }
                }
                if let target = votes.max(by: { $0.value < $1.value })?.key, let first = members.first, let into = big[target]?.first {
                    join(into, first, "signature")
                }
            }
        }
        // Visual suggestions, only for groups that are still small.
        comps = components()
        for pair in suggestions where pair.count == 2 {
            guard let a = unitOf[pair[0]], let b = unitOf[pair[1]] else { continue }
            if fileCount(comps[uf.find(a)] ?? []) < smallClientFiles { join(b, a, "visual") }
        }

        // 6. The designer's own corrections.
        for pair in overrides.clientLinks where pair.count == 2 {
            if let a = unitOf[pair[0]], let b = unitOf[pair[1]] { join(a, b, "manual") }
        }

        // Build collections.
        var components: [Int: [Int]] = [:]
        for i in 0..<n { components[uf.find(i), default: []].append(i) }

        var collections: [Collection] = []
        var hidden: [Collection] = []
        var standalone: [ProjectGroup] = []
        var loose: [CreativeFile] = []
        for (_, members) in components {
            if members.count == 1 {
                let u = units[members[0]]
                if let p = u.project { standalone.append(p) } else if let f = u.file { loose.append(f) }
                continue
            }
            let projects = members.compactMap { units[$0].project }.sorted { $0.lastModified > $1.lastModified }
            let singles = members.compactMap { units[$0].file }.sorted { $0.modified > $1.modified }
            let paths = members.flatMap { units[$0].files.map(\.path) }
            let name = overrides.first(in: overrides.clientNames, for: paths)
                ?? collectionName(members: members, units: units, anchors: anchorOf, brands: brands)
            let id = "collection:" + (projects.first?.id ?? singles.first?.path ?? name)
            let collection = Collection(id: id, name: name, projects: projects, singles: singles)
            if paths.contains(where: overrides.hiddenClients.contains) { hidden.append(collection) } else { collections.append(collection) }
        }
        collections.sort { $0.lastModified > $1.lastModified }
        standalone.sort { $0.lastModified > $1.lastModified }
        loose.sort { $0.modified > $1.modified }
        return Catalog(collections: collections, hidden: hidden, projects: grouping.projects, standalone: standalone, loose: loose)
    }

    static func brandCandidates(_ tokens: [String]) -> [String] {
        NameNormalizer.strongTokens(tokens).filter {
            !deliverableWords.contains($0) && !NameNormalizer.genericFolderWords.contains($0) && !organiserWords.contains($0) && $0.count >= 4
        }
    }

    /// The first folder below a root whose name says something specific. Returns its full path.
    static func anchor(for path: String, roots: [String], depth: Int) -> String? {
        guard let root = roots.filter({ path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) else { return nil }
        let relative = String(path.dropFirst(root.count + 1))
        let parts = relative.split(separator: "/").dropLast().map(String.init)   // folders only
        var current = root
        for folder in parts {
            current += "/" + folder
            let words = NameNormalizer.folderTokens(for: folder).filter { !organiserWords.contains($0) }
            if !words.isEmpty { return current }
        }
        return nil
    }

    static func collectionName(members: [Int], units: [Unit], anchors: [Set<String>], brands: Set<String> = []) -> String {
        // A folder holding most of the collection names it ("Velora Coffee").
        var folderCount: [String: Int] = [:]
        for i in members { for a in anchors[i] { folderCount[a, default: 0] += 1 } }
        // Otherwise the brand word most names share ("Norvia").
        var wordCount: [String: Int] = [:]
        for i in members { for w in Set(brandCandidates(units[i].nameTokens)) { wordCount[w, default: 0] += 1 } }
        // A real brand word ("solara") beats an ordinary one that happens to be frequent ("studio").
        let brandCounts = wordCount.filter { brands.contains($0.key) }
        if let b = brandCounts.max(by: { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }), b.value >= max(2, members.count / 10) {
            wordCount = brandCounts
        }
        let topWord = wordCount.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }
        let topFolder = folderCount.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }

        if let w = topWord, w.value * 2 >= members.count {
            // Prefer the folder spelling when the folder is named after the brand ("Velora Coffee").
            if let f = topFolder, NameNormalizer.folderTokens(for: (f.key as NSString).lastPathComponent).contains(w.key) {
                return prettyFolder(f.key)
            }
            return NameNormalizer.displayName(from: [w.key])
        }
        if let f = topFolder, f.value * 2 >= members.count { return prettyFolder(f.key) }
        if let w = topWord, w.value >= 2 { return NameNormalizer.displayName(from: [w.key]) }
        if let f = topFolder { return prettyFolder(f.key) }
        let biggest = members.compactMap { units[$0].project }.max { $0.files.count < $1.files.count }
        return biggest?.name ?? units[members[0]].files[0].baseName
    }

    static func prettyFolder(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let words = NameNormalizer.tokens(for: name + ".x").filter { !organiserWords.contains($0) }
        return words.isEmpty ? name : NameNormalizer.displayName(from: words)
    }
}

/// The system English word list. Client names are usually invented or foreign words
/// ("Norvia", "Velora", "Solara"), while words like "left" or "grid" are not brands.
enum Dictionary {
    static let words: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }()

    static func contains(_ word: String) -> Bool { words.contains(word) }

    static func isPlural(_ word: String) -> Bool {
        word.hasSuffix("s") && words.contains(String(word.dropLast()))
    }
}
