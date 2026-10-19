import SwiftUI
import AppKit
import QuickLookThumbnailing
import StrataCore

// MARK: - Thumbnails (rendered by macOS Quick Look, so .ai, .psd, .pdf and videos all preview)

@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()
    private let cache = NSCache<NSString, NSImage>()
    /// Files macOS couldn't draw a preview for (shown in Settings › General › Index health).
    private(set) var failed = Set<String>()

    init() { cache.countLimit = 800 }

    func image(for url: URL, side: CGFloat, modified: Date) async -> NSImage? {
        let key = "\(url.path)#\(Int(side))#\(modified.timeIntervalSince1970)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            failed.insert(url.path)
            return nil
        }
        cache.setObject(rep.nsImage, forKey: key)
        return rep.nsImage
    }
}

struct Thumbnail: View {
    let file: CreativeFile
    var side: CGFloat = 320
    @Environment(\.palette) private var palette
    @ViewState private var image: NSImage?

    var body: some View {
        Rectangle()
            .fill(palette.surfaceContainerHighest)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Image(systemName: Format.symbol(for: file.kind)).font(.system(size: 22)).foregroundStyle(palette.outline)
                }
            }
            .animation(.easeOut(duration: 0.25), value: image != nil)
            .clipped()
            .task(id: file.path + "\(file.modified.timeIntervalSince1970)") {
                image = await ThumbnailStore.shared.image(for: file.url, side: side, modified: file.modified)
            }
    }
}

// MARK: - Formatting

enum Format {
    static let day: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f
    }()
    static let dayYear: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM yyyy"); return f
    }()
    static let full: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM yyyy HH:mm"); return f
    }()

    static let dayNumber: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    static let monthShort: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()
    static let monthYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    /// "Oct 17" this year, "Oct 17, 2025" otherwise, so dates never read ambiguously.
    static func date(_ d: Date) -> String {
        Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year) ? day.string(from: d) : dayYear.string(from: d)
    }

    /// "Mar 2 – Oct 17, 2026", or with both years when they differ.
    static func range(_ a: Date, _ b: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(a, inSameDayAs: b) { return dayYear.string(from: b) }
        if cal.isDate(a, equalTo: b, toGranularity: .year) { return "\(day.string(from: a)) – \(dayYear.string(from: b))" }
        return "\(dayYear.string(from: a)) – \(dayYear.string(from: b))"
    }

    /// Plain-language age of a date: "today", "yesterday", "3 days ago", "2 months ago".
    static func ago(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "today" }
        if cal.isDateInYesterday(d) { return "yesterday" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        return f.localizedString(for: d, relativeTo: Date())
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

}

// MARK: - Small shared views

enum FileActions {
    static func open(_ file: CreativeFile) { NSWorkspace.shared.open(file.url) }
    /// Selects the file in its folder: one Finder window.
    static func reveal(_ file: CreativeFile) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
    /// Several files: only the newest is shown, so Finder never opens a window per folder.
    static func reveal(_ files: [CreativeFile]) {
        if let newest = files.max(by: { $0.modified < $1.modified }) { reveal(newest) }
    }
    static func reveal(path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }

    /// A project in Finder: its latest file, selected, in one window.
    static func show(_ project: ProjectGroup) { reveal(project.latest.file) }

    /// A client in Finder: its own folder (the one holding most of its work), opened in one window.
    static func show(_ client: Client) {
        guard let folder = mainFolder(of: client.allFiles) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: folder, isDirectory: true))
    }

    /// The folder most of these files live in, widened to the parent while that still holds most of them
    /// ("Velora Coffee" rather than "Velora Coffee/Exports"), but never a watched root or the home folder.
    static func mainFolder(of files: [CreativeFile]) -> String? {
        guard !files.isEmpty else { return nil }
        var count: [String: Int] = [:]
        for f in files { count[f.folder, default: 0] += 1 }
        guard var folder = count.max(by: { $0.value < $1.value })?.key else { return nil }
        let home = NSHomeDirectory()
        let stops = Set(["Desktop", "Documents", "Downloads", "Movies", "Pictures"].map { home + "/" + $0 } + [home, "/"])
        while true {
            let parent = (folder as NSString).deletingLastPathComponent
            guard !stops.contains(parent), !stops.contains(folder) else { break }
            let inParent = files.filter { $0.path.hasPrefix(parent + "/") }.count
            let inFolder = files.filter { $0.path.hasPrefix(folder + "/") }.count
            guard inParent > inFolder, Double(inParent) >= Double(files.count) * 0.6 else { break }
            folder = parent
        }
        return folder
    }
}

extension View {
    /// Space bar previews the selected file with Quick Look (ignored while typing or moving in the sidebar).
    func spaceToQuickLook(_ url: URL?, preview: Binding<URL?>) -> some View {
        modifier(SpacePreview(url: url, preview: preview))
    }
}

private struct SpacePreview: ViewModifier {
    let url: URL?
    @Binding var preview: URL?
    @ViewState private var monitor: Any?
    @ViewState private var current: URL?

    func body(content: Content) -> some View {
        content
            .onAppear {
                current = url
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let responder = NSApp.keyWindow?.firstResponder
                    guard event.keyCode == 49, !(responder is NSText), !(responder is NSTableView),
                          event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                          let target = current else { return event }
                    preview = preview == nil ? target : nil
                    return nil
                }
            }
            .onChange(of: url) { current = url }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

// MARK: - Build without Xcode

/// The macOS 27 SDK routes `@State` through a SwiftUI compiler macro that only ships with Xcode.
/// This alias points at the same `State` property wrapper, so the app builds with Command Line Tools alone.
typealias ViewState<Value> = SwiftUI.State<Value>
