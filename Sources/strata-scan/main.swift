import Foundation
import StrataCore

// Command-line check of the grouping engine:  strata-scan [folder ...] [--all] [--no-cache]
var args = Array(CommandLine.arguments.dropFirst())
let showAll = args.contains("--all")
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
