import Foundation
import StrataCore

// Command-line check of the grouping engine:  strata-scan [folder ...] [--all] [--no-cache]
var args = Array(CommandLine.arguments.dropFirst())
if args.contains("--recents") {
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
    for (app, list) in RecentFiles.all().sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        print("■ \(app.rawValue)")
        for r in list { print("   \(r.opened.map(df.string) ?? "      —       ")  \(r.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))") }
    }
    exit(0)
}
let showAll = args.contains("--all")
let showCollections = args.contains("--collections")
let showVisual = args.contains("--visual")
let noCache = args.contains("--no-cache")
args.removeAll { $0.hasPrefix("--") }

let home = FileManager.default.homeDirectoryForCurrentUser
let roots = args.isEmpty
    ? ["Desktop", "Downloads", "Documents", "Movies"].map { home.appendingPathComponent($0) }
    : args.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

let scanner = Scanner(cache: MetadataCache(fileURL: noCache ? nil : MetadataCache.defaultURL()))
let scan = scanner.scan(roots: roots)
let started = Date()
let result = Grouper.group(scan.files, roots: roots.map(\.path), hasher: scanner.contentHash)
let groupTime = Date().timeIntervalSince(started)
scanner.cache.save()

let df = DateFormatter()
df.dateFormat = "yyyy-MM-dd HH:mm"
func short(_ path: String) -> String { path.replacingOccurrences(of: home.path, with: "~") }

let withXMP = scan.files.filter { $0.xmp != nil }.count
print("Scanned \(scan.files.count) creative files in \(String(format: "%.2f", scan.duration))s (\(scan.xmpReads) read fresh, \(withXMP) with Adobe IDs)")
print("Grouped into \(result.projects.count) projects + \(result.loose.count) loose files in \(String(format: "%.2f", groupTime))s\n")

if showVisual {
    let catalog = Collector.collect(result, roots: roots.map(\.path))
    let index = VisualIndex(fileURL: VisualIndex.defaultURL())
    if args.contains("--loose-thresholds") { VisualMatcher.threshold = 10; VisualMatcher.margin = 10 }
    let t0 = Date()
    let matches = VisualMatcher.suggest(catalog, index: index)
    print("Visual pass over \(catalog.standalone.count) standalone projects in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s\n")
    for m in matches.sorted(by: { $0.distance < $1.distance }) {
        let name = result.projects.first { $0.first.file.path == m.orphanPath }?.name ?? m.orphanPath
        print(String(format: "%.3f  (next %.3f)  %@  →  %@", m.distance, m.runnerUp, name, m.clientName))
    }
    let merged = Collector.collect(result, roots: roots.map(\.path), suggestions: matches.map { [$0.orphanPath, $0.clientAnchorPath] })
    print("\nAfter visual matching: \(merged.collections.count) clients · \(merged.standalone.count) standalone projects (was \(catalog.collections.count) · \(catalog.standalone.count))")
    for c in merged.collections.sorted(by: { $0.fileCount > $1.fileCount }).prefix(12) {
        print("▣ \(c.name)  —  \(c.projects.count) projects, \(c.fileCount) files")
    }
    exit(0)
}

if showCollections {
    var catalog = Collector.collect(result, roots: roots.map(\.path))
    if args.contains("--with-visual") || CommandLine.arguments.contains("--with-visual") {
        let matches = VisualMatcher.suggest(catalog, index: VisualIndex(fileURL: VisualIndex.defaultURL()))
        catalog = Collector.collect(result, roots: roots.map(\.path), suggestions: matches.map { [$0.orphanPath, $0.clientAnchorPath] })
    }
    print("\(catalog.collections.count) collections · \(catalog.standalone.count) standalone projects · \(catalog.loose.count) loose files\n")
    for c in catalog.collections.sorted(by: { $0.fileCount > $1.fileCount }).prefix(showAll ? .max : 40) {
        let names = c.projects.prefix(showAll ? 999 : 6).map(\.name).joined(separator: ", ")
        print("▣ \(c.name)  —  \(c.projects.count) projects, \(c.singles.count) single files (\(c.fileCount) files)")
        if !names.isEmpty { print("     projects: \(names)\(c.projects.count > 6 && !showAll ? ", …" : "")") }
        if !c.singles.isEmpty { print("     singles:  \(c.singles.prefix(4).map(\.name).joined(separator: ", "))\(c.singles.count > 4 ? ", …" : "")") }
    }
    exit(0)
}

for p in result.projects.prefix(showAll ? .max : 25) {
    var flags: [String] = []
    if p.hasRecovered { flags.append("recovered") }
    if p.duplicateCount > 0 { flags.append("\(p.duplicateCount) duplicate") }
    print("■ \(p.name)  —  \(p.files.count) files · \(p.extensions.joined(separator: "/"))\(flags.isEmpty ? "" : "  [\(flags.joined(separator: ", "))]")")
    for v in p.versions {
        let mark = v.id == p.first.id ? "◆ first " : (v.id == p.latest.id ? "★ latest" : "  ·     ")
        print("   \(mark) \(df.string(from: v.file.modified))  \(short(v.file.path))   ← \(v.reason.label)\(v.isDuplicate ? " (duplicate)" : "")")
        for e in p.exports(of: v) {
            print("              ↳ export \(df.string(from: e.file.modified))  \(short(e.file.path))   ← \(e.reason.label)")
        }
    }
    print("")
}
if !showAll && result.projects.count > 25 { print("… \(result.projects.count - 25) more projects (use --all)") }
