import Foundation

/// Pulls Adobe's document identifiers out of the XMP packet embedded in a file.
///
/// Adobe apps write `xmpMM:DocumentID` (changes on Save As), `xmpMM:OriginalDocumentID`
/// (kept across Save As and crash recovery) and `xmpMM:DerivedFrom` (the file this one came from).
/// The packet usually sits near the start of .ai/.psd/.pdf files and near the end of videos,
/// so we read a slice from each end instead of the whole file.
public enum XMPReader {
    public static let headBytes = 2 << 20   // 2 MB
    public static let tailBytes = 1 << 20   // 1 MB

    public static func read(url: URL) -> XMPInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        let head = (try? handle.read(upToCount: headBytes)) ?? Data()
        if let info = parse(data: head) { return info }
        guard size > UInt64(headBytes) else { return nil }
        let start = max(UInt64(headBytes), size - UInt64(tailBytes))
        try? handle.seek(toOffset: start)
        let tail = (try? handle.read(upToCount: tailBytes)) ?? Data()
        return parse(data: tail)
    }

    private static let openTag = Data("<x:xmpmeta".utf8)
    private static let closeTag = Data("</x:xmpmeta>".utf8)

    /// Parses the first XMP packet in `data`. The first packet is the document's own;
    /// later ones belong to embedded thumbnails or placed images.
    public static func parse(data: Data) -> XMPInfo? {
        var searchFrom = data.startIndex
        while let start = data.range(of: openTag, in: searchFrom..<data.endIndex) {
            let limit = min(data.endIndex, start.lowerBound + 1_000_000)
            guard let end = data.range(of: closeTag, in: start.upperBound..<limit) else { return nil }
            let packet = data[start.lowerBound..<end.upperBound]
            let xml = String(data: packet, encoding: .utf8) ?? String(data: packet, encoding: .isoLatin1) ?? ""
            if let info = parse(xml: xml) { return info }
            searchFrom = end.upperBound
        }
        return nil
    }

    public static func parse(xml raw: String) -> XMPInfo? {
        // Drop lists that describe *other* documents (placed files, history, linked assets).
        var xml = raw
        for block in ["xmpMM:Pantry", "xmpMM:Ingredients", "xmpMM:Manifest", "xmpMM:History", "photoshop:DocumentAncestors"] {
            xml = removeBlocks(named: block, from: xml)
        }

        var derived: [String] = []
        for block in blocks(named: "xmpMM:DerivedFrom", in: xml) {
            // Only the exact source document. Its originalDocumentID is shared by the whole Save As family.
            if let id = value(of: "stRef:documentID", in: block) { derived.append(id) }
        }
        xml = removeBlocks(named: "xmpMM:DerivedFrom", from: xml)

        var fonts: [String] = []
        for block in blocks(named: "xmpTPg:Fonts", in: xml) {
            for raw in all(of: "stFnt:fontFamily", in: block) {
                let name = raw.replacingOccurrences(of: "^[A-Z]{6}\\+", with: "", options: .regularExpression)
                if !fonts.contains(name) { fonts.append(name) }
            }
        }
        let info = XMPInfo(
            documentID: value(of: "xmpMM:DocumentID", in: xml),
            originalDocumentID: value(of: "xmpMM:OriginalDocumentID", in: xml),
            instanceID: value(of: "xmpMM:InstanceID", in: xml),
            derivedFromIDs: Array(Set(derived)).sorted(),
            creatorTool: value(of: "xmp:CreatorTool", in: xml, normalize: false),
            fonts: fonts
        )
        return info.isEmpty ? nil : info
    }

    // MARK: - Tiny XML helpers (XMP is regular enough that regex beats a full parser here)

    static func value(of name: String, in xml: String, normalize: Bool = true) -> String? {
        let n = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "\(n)\\s*=\\s*\"([^\"]*)\"",
            "\(n)\\s*=\\s*'([^']*)'",
            "<\(n)>\\s*([^<]*?)\\s*</\(n)>",
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
                  let r = Range(m.range(at: 1), in: xml) else { continue }
            let v = String(xml[r])
            if normalize { if let id = normalizeID(v) { return id } } else if !v.isEmpty { return v }
        }
        return nil
    }

    /// Every value of `name` (element or attribute form), in order.
    static func all(of name: String, in xml: String) -> [String] {
        let n = NSRegularExpression.escapedPattern(for: name)
        var out: [String] = []
        for pattern in ["\(n)\\s*=\\s*\"([^\"]*)\"", "<\(n)>\\s*([^<]*?)\\s*</\(n)>"] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in re.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
                if let r = Range(m.range(at: 1), in: xml) {
                    let v = String(xml[r]).trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { out.append(v) }
                }
            }
        }
        return out
    }

    /// Lowercases and drops empty / placeholder identifiers.
    public static func normalizeID(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard v.count >= 8 else { return nil }
        let body = v.split(separator: ":").last.map(String.init) ?? v
        if body.allSatisfy({ $0 == "0" || $0 == "-" }) { return nil }
        return v
    }

    private static func blockRegex(_ name: String) -> NSRegularExpression? {
        let n = NSRegularExpression.escapedPattern(for: name)
        return try? NSRegularExpression(pattern: "<\(n)\\b[^>]*?(?:/>|>.*?</\(n)>)", options: [.dotMatchesLineSeparators])
    }

    static func blocks(named name: String, in xml: String) -> [String] {
        guard let re = blockRegex(name) else { return [] }
        return re.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap {
            Range($0.range, in: xml).map { String(xml[$0]) }
        }
    }

    static func removeBlocks(named name: String, from xml: String) -> String {
        guard let re = blockRegex(name) else { return xml }
        return re.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: "")
    }
}
