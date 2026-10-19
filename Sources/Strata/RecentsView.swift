import SwiftUI
import AppKit
import StrataCore

/// What each Adobe app opened last, read from the apps' own Open Recent lists.
@MainActor
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()
    @Published private(set) var byApp: [AdobeApp: [RecentFile]] = [:]
    @Published private(set) var updated: Date?

    func refresh() {
        Task.detached(priority: .utility) {
            let all = RecentFiles.all(limit: 8)
            await MainActor.run {
                RecentsStore.shared.byApp = all
                RecentsStore.shared.updated = Date()
            }
        }
    }

    var apps: [AdobeApp] { AdobeApp.allCases.filter { !(byApp[$0] ?? []).isEmpty } }

    /// The installed app itself (for its icon and to open files in it, not in Preview).
    static func appURL(_ app: AdobeApp) -> URL? {
        let exact: [AdobeApp: String] = [.illustrator: "com.adobe.illustrator", .photoshop: "com.adobe.Photoshop",
                                         .indesign: "com.adobe.InDesign", .afterEffects: "com.adobe.AfterEffects"]
        if let id = exact[app], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        let apps = URL(fileURLWithPath: "/Applications")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: apps.path))?
            .filter { $0.hasPrefix(app.appFolderPrefix) }.sorted().reversed() ?? []
        for folder in folders {
            let dir = apps.appendingPathComponent(folder)
            if let bundle = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.first(where: { $0.hasSuffix(".app") }) {
                return dir.appendingPathComponent(bundle)
            }
        }
        return nil
    }

    static func icon(_ app: AdobeApp) -> NSImage? {
        appURL(app).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    static func open(_ file: RecentFile) {
        guard let appURL = appURL(file.app) else { NSWorkspace.shared.open(file.url); return }
        NSWorkspace.shared.open([file.url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct RecentsView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var store = RecentsStore.shared
    @Environment(\.palette) private var palette
    let showProject: (String) -> Void
    @ViewState private var preview: URL?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recently opened").font(.display(44)).foregroundStyle(palette.onSurface)
                        Text("The last files each app opened, from their own Open Recent lists. For when you remember the work, not the file name.")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button { store.refresh() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold)).fixedSize()
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(palette.secondaryContainer, in: Capsule())
                            .foregroundStyle(palette.onSecondaryContainer)
                    }
                    .buttonStyle(PressScale())
                }
                if store.apps.isEmpty {
                    Text(store.updated == nil ? "Reading Illustrator and Photoshop…" : "No recently opened Adobe files found.")
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
                ForEach(store.apps) { app in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            if let icon = RecentsStore.icon(app) {
                                Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                            }
                            Text(app.rawValue).font(.display(24)).foregroundStyle(palette.onSurface)
                            Text("\(store.byApp[app]?.count ?? 0) files").font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            ForEach(store.byApp[app] ?? []) { recent in
                                RecentCard(recent: recent, showProject: showProject) { preview = recent.url }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 28)
        }
        .background(palette.surface)
        .scrollFade()
        .quickLookPreview($preview)
        .onAppear { store.refresh() }
    }
}

private struct RecentCard: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    let recent: RecentFile
    let showProject: (String) -> Void
    let preview: () -> Void

    var body: some View {
        let file = library.file(at: recent.path)
        let project = library.projects.first { p in p.files.contains { $0.file.path == recent.path } }
        let client = project.flatMap { library.collection(containing: $0.id) }
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let file {
                    Thumbnail(file: file, side: 260)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: recent.path)).resizable().scaledToFit().padding(24)
                        .background(palette.surfaceContainerHighest)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture(perform: preview)
            Text(recent.name).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.onSurface)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(recent.opened.map { "Opened \(Format.ago($0))" } ?? Format.folder(recent.path))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            if let project {
                Button { showProject(project.id) } label: {
                    Label([client?.name, project.name].compactMap { $0 }.joined(separator: " · "), systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(palette.secondaryContainer, in: Capsule())
                        .foregroundStyle(palette.onSecondaryContainer)
                }
                .buttonStyle(PressScale())
                .help("Show this project's timeline")
            }
            HStack(spacing: 6) {
                Button("Open in \(recent.app.rawValue)") { RecentsStore.open(recent) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button { FileActions.reveal(path: recent.path) } label: { Image(systemName: "folder") }
                    .controlSize(.small).help("Show in Finder")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.surfaceContainerLow))
        .materialContextMenu {
            Button("Open in \(recent.app.rawValue)") { RecentsStore.open(recent) }
            Button("Show in Finder") { FileActions.reveal(path: recent.path) }
        }
    }
}
