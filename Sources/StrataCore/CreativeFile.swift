import Foundation

/// Adobe XMP identifiers that survive Save As, crash recovery and exports.
public struct XMPInfo: Codable, Hashable, Sendable {
    public var documentID: String?
    public var originalDocumentID: String?
    public var instanceID: String?
    /// Document IDs of the file(s) this one was saved or exported from.
    public var derivedFromIDs: [String]
    public var creatorTool: String?

    public init(documentID: String? = nil, originalDocumentID: String? = nil, instanceID: String? = nil,
                derivedFromIDs: [String] = [], creatorTool: String? = nil) {
        self.documentID = documentID
        self.originalDocumentID = originalDocumentID
        self.instanceID = instanceID
        self.derivedFromIDs = derivedFromIDs
        self.creatorTool = creatorTool
    }

    public var isEmpty: Bool { documentID == nil && originalDocumentID == nil && derivedFromIDs.isEmpty }
}

/// One file on disk that Strata knows about. Strata only ever reads these.
public struct CreativeFile: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let kind: FileKind
    public let size: Int64
    public let created: Date
    public let modified: Date
    public var xmp: XMPInfo?
    public var contentHash: String?

    public init(path: String, kind: FileKind, size: Int64, created: Date, modified: Date,
                xmp: XMPInfo? = nil, contentHash: String? = nil) {
        self.path = path
        self.kind = kind
        self.size = size
        self.created = created
        self.modified = modified
        self.xmp = xmp
        self.contentHash = contentHash
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
    public var baseName: String { (name as NSString).deletingPathExtension }
    public var fileExtension: String { (name as NSString).pathExtension.uppercased() }
    public var folder: String { (path as NSString).deletingLastPathComponent }

    /// Saved by an app after a crash (Illustrator / Photoshop "(Recovered)", autosave folders).
    public var isRecovered: Bool {
        let n = name.lowercased()
        return n.contains("recovered") || n.contains("récupéré") || n.contains("recupere")
            || path.contains("/Autosave/") || path.contains("/AutoRecover/")
    }
}
