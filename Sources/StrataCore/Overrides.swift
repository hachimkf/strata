import Foundation

/// Corrections the designer made by hand. They always win over the automatic grouping.
///
/// Everything is keyed by file path, which survives rescans (project and client ids are derived
/// from their files and can change when files come and go).
public struct Overrides: Codable, Equatable, Sendable {
    /// Pairs of files forced into the same project.
    public var links: [[String]] = []
    /// Files pulled out of every automatic project link (they become loose unless linked by hand).
    public var detached: Set<String> = []
    /// Pairs of files whose projects are forced into the same client.
    public var clientLinks: [[String]] = []
    /// Files whose project is kept out of every automatic client grouping.
    public var clientDetached: Set<String> = []
    /// A client containing this file is shown with this name.
    public var clientNames: [String: String] = [:]
    /// A project containing this file is shown with this name.
    public var projectNames: [String: String] = [:]
    /// A client containing this file is hidden.
    public var hiddenClients: Set<String> = []
    /// Folders never scanned.
    public var hiddenFolders: [String] = []
    /// A note written on a version.
    public var notes: [String: String] = [:]
    /// Starred clients and projects (by any of their files).
    public var favorites: Set<String> = []

    public init() {}

    // Tolerant decoding: a file written by an older version simply lacks the newer fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        links = try c.decodeIfPresent([[String]].self, forKey: .links) ?? []
        detached = try c.decodeIfPresent(Set<String>.self, forKey: .detached) ?? []
        clientLinks = try c.decodeIfPresent([[String]].self, forKey: .clientLinks) ?? []
        clientDetached = try c.decodeIfPresent(Set<String>.self, forKey: .clientDetached) ?? []
        clientNames = try c.decodeIfPresent([String: String].self, forKey: .clientNames) ?? [:]
        projectNames = try c.decodeIfPresent([String: String].self, forKey: .projectNames) ?? [:]
        hiddenClients = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenClients) ?? []
        hiddenFolders = try c.decodeIfPresent([String].self, forKey: .hiddenFolders) ?? []
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
        favorites = try c.decodeIfPresent(Set<String>.self, forKey: .favorites) ?? []
    }

    public var isEmpty: Bool { self == Overrides() }

    public static func load(from url: URL) -> Overrides {
        guard let data = try? Data(contentsOf: url), let o = try? JSONDecoder().decode(Overrides.self, from: data) else { return Overrides() }
        return o
    }

    public func save(to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) { SecureStore.write(data, to: url) }
    }

    public static func defaultURL() -> URL {
        MetadataCache.defaultURL().deletingLastPathComponent().appendingPathComponent("corrections.json")
    }

    /// First value whose key is one of `paths`.
    func first<V>(in map: [String: V], for paths: [String]) -> V? {
        for p in paths { if let v = map[p] { return v } }
        return nil
    }
}

/// Workflow status of a version, stored as a Finder tag so Finder and other apps see it too.
public enum VersionStatus: String, CaseIterable, Codable, Sendable {
    case draft = "Draft"
    case inReview = "In Review"
    case sent = "Sent"
    case approved = "Approved"
    case final = "Final"

    public static func from(tags: [String]) -> VersionStatus? {
        // The most advanced status wins if several tags are present.
        allCases.reversed().first { tags.contains($0.rawValue) }
    }

    public var symbol: String {
        switch self {
        case .draft: return "pencil"
        case .inReview: return "eye"
        case .sent: return "paperplane.fill"
        case .approved: return "hand.thumbsup.fill"
        case .final: return "checkmark.seal.fill"
        }
    }
}

public enum FinderTags {
    /// Replaces any Strata status tag on the file with `status` (or removes it), keeping the user's other tags.
    public static func set(_ status: VersionStatus?, on path: String) throws {
        let url = URL(fileURLWithPath: path)
        let current = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        var tags = current.filter { tag in !VersionStatus.allCases.contains { $0.rawValue == tag } }
        if let status { tags.append(status.rawValue) }
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }
}
