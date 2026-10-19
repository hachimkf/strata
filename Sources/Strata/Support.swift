import SwiftUI
import AppKit
import QuickLookThumbnailing
import StrataCore

// MARK: - Thumbnails (rendered by macOS Quick Look, so .ai, .psd, .pdf and videos all preview)

@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 800 }

    func image(for url: URL, side: CGFloat, modified: Date) async -> NSImage? {
        let key = "\(url.path)#\(Int(side))#\(modified.timeIntervalSince1970)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        cache.setObject(rep.nsImage, forKey: key)
        return rep.nsImage
    }
}

struct Thumbnail: View {
    let file: CreativeFile
    var side: CGFloat = 320
    @ViewState private var image: NSImage?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .quaternarySystemFill))
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: Format.symbol(for: file.kind)).font(.system(size: 22)).foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: file.path + "\(file.modified.timeIntervalSince1970)") {
                image = await ThumbnailStore.shared.image(for: file.url, side: side, modified: file.modified)
            }
    }
}

// MARK: - Formatting

enum Format {
    static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    static let dayYear: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    static let full: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    static func date(_ d: Date) -> String {
        Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year) ? day.string(from: d) : dayYear.string(from: d)
    }

    /// Time between two saves, for the pills on the timeline.
    static func gap(from a: Date, to b: Date) -> String {
        let s = b.timeIntervalSince(a)
        let days = s / 86400
        if days < 1 {
            let hours = Int(s / 3600)
            return hours < 1 ? "minutes later" : "+\(hours) h"
        }
        if days < 14 { return "+\(Int(days)) day\(Int(days) == 1 ? "" : "s")" }
        if days < 60 { return "+\(Int(days / 7)) weeks" }
        if days < 365 { return "+\(Int(days / 30)) months" }
        let years = days / 365
        return years < 2 ? "+1 year" : "+\(Int(years)) years"
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    /// "~/Documents/Clients/Atlas"
    static func folder(_ path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Last folder name only: "Atlas"
    static func shortFolder(_ path: String) -> String {
        ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
    }

    static func symbol(for kind: FileKind) -> String {
        switch kind {
        case .illustrator, .vector: return "pencil.and.outline"
        case .photoshop, .image: return "photo"
        case .indesign, .pdf: return "doc.richtext"
        case .afterEffects, .premiere, .video: return "film"
        }
    }

    static func color(forExtension ext: String) -> Color {
        switch ext {
        case "AI", "EPS", "AIT", "SVG": return Color(red: 0.85, green: 0.45, blue: 0.05)
        case "PSD", "PSB": return Color(red: 0.12, green: 0.42, blue: 0.85)
        case "INDD": return Color(red: 0.85, green: 0.15, blue: 0.45)
        case "AEP", "PRPROJ", "MP4", "MOV", "M4V": return Color(red: 0.45, green: 0.28, blue: 0.80)
        case "PDF": return Color(red: 0.80, green: 0.18, blue: 0.15)
        default: return Color(red: 0.12, green: 0.55, blue: 0.35)
        }
    }
}

// MARK: - Small shared views

struct KindChip: View {
    let text: String
    var color: Color? = nil
    var body: some View {
        let c = color ?? Format.color(forExtension: text)
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(c.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(c)
    }
}

enum FileActions {
    static func open(_ file: CreativeFile) { NSWorkspace.shared.open(file.url) }
    static func reveal(_ file: CreativeFile) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
    static func reveal(_ files: [CreativeFile]) { NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url)) }
}

// MARK: - Build without Xcode

/// The macOS 27 SDK routes `@State` through a SwiftUI compiler macro that only ships with Xcode.
/// This alias points at the same `State` property wrapper, so the app builds with Command Line Tools alone.
typealias ViewState<Value> = SwiftUI.State<Value>
