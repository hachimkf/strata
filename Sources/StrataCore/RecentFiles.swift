import Foundation
import CoreServices

/// The Adobe apps Strata knows the "recently opened" list of.
public enum AdobeApp: String, CaseIterable, Sendable, Identifiable {
    case illustrator = "Illustrator"
    case photoshop = "Photoshop"
    case indesign = "InDesign"
    case afterEffects = "After Effects"
    case premiere = "Premiere Pro"

    public var id: String { rawValue }

    /// Bundle identifier prefix (Premiere's includes its version).
    public var bundlePrefix: String {
        switch self {
        case .illustrator: return "com.adobe.illustrator"
        case .photoshop: return "com.adobe.Photoshop"
        case .indesign: return "com.adobe.InDesign"
        case .afterEffects: return "com.adobe.AfterEffects"
        case .premiere: return "com.adobe.PremierePro"
        }
    }

    /// Folder-name prefix in /Applications ("Adobe Illustrator 2026").
    public var appFolderPrefix: String { "Adobe \(rawValue)" }

    var documentExtensions: [String] {
        switch self {
        case .illustrator: return ["ai", "eps", "ait"]
        case .photoshop: return ["psd", "psb"]
        case .indesign: return ["indd"]
        case .afterEffects: return ["aep"]
        case .premiere: return ["prproj"]
        }
    }
}

public struct RecentFile: Identifiable, Hashable, Sendable {
    public var id: String { app.rawValue + "|" + path }
    public let path: String
    public let app: AdobeApp
    /// When the app last opened it (exact for Illustrator; Spotlight's "last opened" otherwise).
    public let opened: Date?
    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
}

/// Reads the "recently opened" lists the Adobe apps keep, like Open Recent in their File menu.
public enum RecentFiles {
    public static func all(limit: Int = 8) -> [AdobeApp: [RecentFile]] {
        var out: [AdobeApp: [RecentFile]] = [:]
        out[.illustrator] = Array(illustrator().prefix(limit))
        out[.photoshop] = Array(photoshop().prefix(limit))
        for app in [AdobeApp.indesign, .afterEffects, .premiere] {
            let list = spotlight(app)
            if !list.isEmpty { out[app] = Array(list.prefix(limit)) }
        }
        return out.filter { !$0.value.isEmpty }
    }

    // MARK: Illustrator: Preferences/Adobe Illustrator NN Settings/<locale>/Adobe Illustrator Prefs

    /// Illustrator writes its Open Recent list as `/MixedFileList { /fileN { /lastOpentime [hex] /path [hex] } }`.
    public static func illustrator() -> [RecentFile] {
        guard let prefs = newestSettings(prefix: "Adobe Illustrator ", suffix: " Settings")
            .flatMap({ dir in
                (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
                    .map { dir.appendingPathComponent($0).appendingPathComponent("Adobe Illustrator Prefs") }
                    .first { FileManager.default.fileExists(atPath: $0.path) }
            }),
            let raw = try? Data(contentsOf: prefs) else { return [] }
        let text = String(decoding: raw, as: UTF8.self)
        guard let start = text.range(of: "/MixedFileList") else { return [] }
        let block = String(text[start.lowerBound...].prefix(400_000))

        // Each entry is "/fileN { … }" with /lastOpentime and /path in any order: split, then search each part.
        let split = try! NSRegularExpression(pattern: #"/file\d+\s*\{"#)
        let time = try! NSRegularExpression(pattern: #"/lastOpentime\s*\[\s*\d+\s+([0-9a-fA-F\s]+?)\]"#)
        let pathRE = try! NSRegularExpression(pattern: #"/path\s*\[\s*\d+\s+([0-9a-fA-F\s]+?)\]"#)
        let iso = ISO8601DateFormatter()
        let starts = split.matches(in: block, range: NSRange(block.startIndex..., in: block)).map(\.range.location)
        let ns = block as NSString
        var out: [RecentFile] = []
        for (k, start) in starts.enumerated() {
            let end = k + 1 < starts.count ? starts[k + 1] : min(ns.length, start + 4000)
            let part = ns.substring(with: NSRange(location: start, length: end - start))
            func capture(_ re: NSRegularExpression) -> String? {
                guard let m = re.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)),
                      let r = Range(m.range(at: 1), in: part) else { return nil }
                return hexString(String(part[r]))
            }
            guard let path = capture(pathRE) else { continue }
            out.append(RecentFile(path: path, app: .illustrator, opened: capture(time).flatMap { iso.date(from: $0) }))
        }
        return existing(out).sorted { ($0.opened ?? .distantPast) > ($1.opened ?? .distantPast) }
    }

    // MARK: Photoshop: Preferences/Adobe Photoshop YYYY Settings/MachinePrefs.psp (UTF-16 paths, newest first)

    public static func photoshop() -> [RecentFile] {
        guard let dir = newestSettings(prefix: "Adobe Photoshop ", suffix: " Settings"),
              let raw = try? Data(contentsOf: dir.appendingPathComponent("MachinePrefs.psp")) else { return [] }
        // UTF-16 little-endian; decoding repairs any stray bytes instead of failing.
        let units = stride(from: 0, to: raw.count - 1, by: 2).map { UInt16(raw[$0]) | UInt16(raw[$0 + 1]) << 8 }
        let text = String(decoding: units, as: UTF16.self)
        let re = try! NSRegularExpression(pattern: #"/Users/[^\u0000\n\r]{1,300}?\.(?:psd|psb|png|jpe?g|tiff?|gif|webp|heic|pdf)"#,
                                          options: [.caseInsensitive])
        var seen = Set<String>()
        var out: [RecentFile] = []
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            let path = String(text[r])
            guard seen.insert(path.lowercased()).inserted else { continue }
            out.append(RecentFile(path: path, app: .photoshop, opened: lastUsed(path)))
        }
        return existing(out)
    }

    // MARK: Other apps: Spotlight's "last opened" date for their document types

    public static func spotlight(_ app: AdobeApp, days: Int = 90) -> [RecentFile] {
        let names = app.documentExtensions.map { "kMDItemFSName == \"*.\($0)\"c" }.joined(separator: " || ")
        let query = "kMDItemLastUsedDate >= $time.today(-\(days)) && (\(names))"
        guard let q = MDQueryCreate(kCFAllocatorDefault, query as CFString, nil, nil),
              MDQueryExecute(q, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var out: [RecentFile] = []
        for i in 0..<MDQueryGetResultCount(q) {
            guard let raw = MDQueryGetResultAtIndex(q, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            out.append(RecentFile(path: path, app: app, opened: MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date))
        }
        return out.sorted { ($0.opened ?? .distantPast) > ($1.opened ?? .distantPast) }
    }

    // MARK: Helpers

    /// The highest-numbered "Adobe X NN Settings" folder (the version in use).
    static func newestSettings(prefix: String, suffix: String) -> URL? {
        let prefs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: prefs.path)) ?? []
        let matches = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
            .compactMap { name -> (Int, String)? in
                let middle = name.dropFirst(prefix.count).dropLast(suffix.count)
                return Int(middle).map { ($0, name) }
            }
        return matches.max { $0.0 < $1.0 }.map { prefs.appendingPathComponent($0.1) }
    }

    static func hexString(_ hex: String) -> String? {
        let clean = hex.filter(\.isHexDigit)
        guard clean.count % 2 == 0, !clean.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(clean.count / 2)
        var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            guard let b = UInt8(clean[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func lastUsed(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Files still on disk, outside app support folders (Illustrator's new-document templates etc.).
    static func existing(_ list: [RecentFile]) -> [RecentFile] {
        let fm = FileManager.default
        return list.filter { !$0.path.contains("/Library/Application Support/") && fm.fileExists(atPath: $0.path) }
    }
}
