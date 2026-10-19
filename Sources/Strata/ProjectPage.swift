import SwiftUI
import AppKit
import AVFoundation
import QuickLook
import StrataCore

/// One project: toolbar with breadcrumb, a large preview of the selected version, the version filmstrip,
/// and a details panel with status, note and the version timeline. The zoomable river timeline is one click away.
struct ProjectDetailView: View {
    let project: ProjectGroup
    var client: Client? = nil
    let navigation: PageNavigation

    var body: some View {
        DetailContent(project: project, client: client, navigation: navigation)
            .artworkPalette(project.latest.file, name: project.name)
            .navigationTitle(project.name)
    }
}

/// Ask the timeline to bring a version to the centre of the screen.
struct FocusRequest: Equatable {
    let id: String
    let token = UUID()
}

/// Actions any version view in the project page can trigger.
struct VersionActions {
    var compare: (ProjectFile) -> Void = { _ in }
    var move: (ProjectFile) -> Void = { _ in }
}

private struct VersionActionsKey: EnvironmentKey { static let defaultValue = VersionActions() }
extension EnvironmentValues {
    var versionActions: VersionActions {
        get { self[VersionActionsKey.self] }
        set { self[VersionActionsKey.self] = newValue }
    }
}

/// Which two versions the compare screen opens with.
struct ComparePair: Identifiable, Equatable {
    let left: String
    let right: String
    var id: String { left + "|" + right }
}

enum ProjectViewMode: String { case preview, timeline }

private struct DetailContent: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    let project: ProjectGroup
    let client: Client?
    let navigation: PageNavigation

    @AppStorage("projectViewMode") private var mode: ProjectViewMode = .preview
    @ViewState private var selectedID: String?
    @ViewState private var preview: URL?
    @ViewState private var revealed = false
    @ViewState private var playing = false
    @ViewState private var playTask: Task<Void, Never>?
    @ViewState private var focus: FocusRequest?
    @ViewState private var keyMonitor: Any?
    @ViewState private var comparing: ComparePair?
    @ViewState private var renaming = false
    @ViewState private var movingFile: ProjectFile?
    @ViewState private var choosingClient = false
    @ViewState private var search = ""

    private var selected: ProjectFile { project.files.first { $0.id == selectedID } ?? project.latest }
    private var layout: TimelineLayout { TimelineLayout(versions: project.versions) }

    /// Versions matching the "Search in project" field (name or note).
    private var shownVersions: [ProjectFile] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return project.versions }
        return project.versions.filter { v in
            v.file.name.lowercased().contains(q) || library.note(for: v.file).lowercased().contains(q)
                || project.exports(of: v).contains { $0.file.name.lowercased().contains(q) }
        }
    }

    var body: some View {
        Group {
            if let pair = comparing {
                CompareView(project: project, client: client, left: pair.left, right: pair.right) {
                    withAnimation(Motion.standard) { comparing = nil }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    toolbar.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 14) {
                            if mode == .preview {
                                LargePreview(file: selected, version: versionNumber(selected))
                                    .onTapGesture(count: 2) { FileActions.open(selected.file) }
                                VersionFilmstrip(project: project, versions: shownVersions, selectedID: selected.id,
                                                 select: { select($0) })
                                    .frame(height: 218)
                            } else {
                                Overview(project: project, selectedID: selected.id) { select($0) }
                                TimelineViewport(project: project, layout: layout, selectedID: selected.id, revealed: revealed,
                                                 focus: focus, select: { select($0) }, open: { FileActions.open($0.file) })
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        DetailsPanel(project: project, file: selected, versions: shownVersions, search: $search,
                                     select: { select($0) }, preview: { preview = $0.file.url })
                            .frame(width: 340)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 18)
                }
                .transition(.opacity)
            }
        }
        .background(palette.surface)
        .environment(\.versionActions, VersionActions(compare: { compare($0) }, move: { movingFile = $0 }))
        .sheet(isPresented: $renaming) {
            NamePrompt(title: "Rename project", initial: project.name) { library.rename(project, to: $0) }
        }
        .sheet(item: $movingFile) { file in
            PickerSheet(title: "Move \(file.file.name) to…",
                        items: library.projects.filter { $0.id != project.id }.map {
                            PickItem(id: $0.id, title: $0.name,
                                     subtitle: [library.collection(containing: $0.id)?.name, "\($0.versions.count) versions"].compactMap { $0 }.joined(separator: " · "),
                                     file: $0.latest.file)
                        }) { item in
                if let target = library.project(id: item.id) { library.move(file.file, toProjectOf: target) }
            }
        }
        .sheet(isPresented: $choosingClient) {
            PickerSheet(title: "Move \(project.name) to client…",
                        items: library.collections.map {
                            PickItem(id: $0.id, title: $0.name, subtitle: "\($0.projects.count) projects", file: $0.latest)
                        }) { item in
                if let c = library.collection(id: item.id) { library.assign(project.first.file, to: c) }
            }
        }
        .onAppear {
            revealed = true
            installKeys()
        }
        .onDisappear {
            playTask?.cancel()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .quickLookPreview($preview)
    }

    private func versionNumber(_ f: ProjectFile) -> Int? {
        project.versions.firstIndex { $0.id == (f.exportOf ?? f.id) }.map { $0 + 1 }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { navButtons; breadcrumb; Spacer(minLength: 12); actions(compact: false).fixedSize() }
            HStack(spacing: 14) { navButtons; breadcrumb; Spacer(minLength: 12); actions(compact: true).fixedSize() }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) { navButtons; breadcrumb }
                actions(compact: true).fixedSize()
            }
        }
    }

    private var navButtons: some View {
        HStack(spacing: 0) {
            Button(action: navigation.back) {
                Image(systemName: "chevron.left").frame(width: 40, height: 38).contentShape(Rectangle())
            }
            .keyboardShortcut("[", modifiers: .command)
            .help("Back (⌘[)")
            Divider().frame(height: 18)
            Button { navigation.forward?() } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 38).contentShape(Rectangle())
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(navigation.forward == nil)
            .help("Forward (⌘])")
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(palette.onSurface)
        .tonalSurface(Capsule())
    }

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(palette.onSurfaceVariant)
            if let client {
                Button { navigation.openClient(client.id) } label: {
                    Text(client.name).font(.system(size: 15, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .help("Open \(client.name)")
                Text("/").foregroundStyle(palette.outline)
            }
            Text(project.name).font(.display(22)).foregroundStyle(palette.onSurface).lineLimit(1)
            MaterialMenu {
                Button(library.isFavorite(project) ? "Remove from Favorites" : "Add to Favorites") { library.toggleFavorite(project) }
                Button("Rename project…") { renaming = true }
                if let client {
                    Button("Remove from \(client.name)") { library.removeFromClient(project) }
                }
                Button("Move to client…") { choosingClient = true }
                Divider()
                Button("Show all files in Finder") { FileActions.reveal(project.files.map(\.file)) }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.onSurfaceVariant)
            }
            .fixedSize()
            .help("Project options")
        }
        .lineLimit(1)
    }

    private func actions(compact: Bool) -> some View {
        HStack(spacing: 10) {
            ButtonGroup(items: [(ProjectViewMode.preview, "", "photo"), (.timeline, "", "point.3.connected.trianglepath.dotted")],
                        selection: $mode, height: 34, grouped: true)
                .help("Preview or zoomable timeline")
            if project.versions.count > 1 {
                Button { toggleReplay() } label: {
                    Image(systemName: playing ? "stop.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(palette.onSurface)
                        .tonalSurface(Circle())
                }
                .buttonStyle(PressScale())
                .help(playing ? "Stop" : "Replay the history, first version to latest")
                Button { comparing = ComparePair(left: project.versions[project.versions.count - 2].id, right: project.latest.id) } label: {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                        .labelStyle(AdaptiveLabel(iconOnly: compact))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, compact ? 0 : 18).frame(minWidth: 42).frame(height: 42)
                        .foregroundStyle(palette.onSurface)
                        .tonalSurface(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .help("Compare the two latest versions")
            }
            if let approved = project.approved {
                Button { FileActions.open(approved.file) } label: {
                    Label("Open \(approved.file.status?.rawValue ?? "approved")", systemImage: "checkmark.seal.fill")
                        .labelStyle(AdaptiveLabel(iconOnly: compact))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, compact ? 0 : 16).frame(minWidth: 42).frame(height: 42)
                        .foregroundStyle(palette.onSurface)
                        .tonalSurface(Capsule(), tint: palette.tertiary.opacity(0.35))
                }
                .buttonStyle(PressScale())
                .help("Open \(approved.file.name)")
            }
            SplitButton(title: "Open latest", symbol: "arrow.up.forward.square", action: {
                withAnimation(Motion.standard) { selectedID = project.latest.id }
                FileActions.open(project.latest.file)
            }) {
                Button("Open \(project.latest.file.name)") { FileActions.open(project.latest.file) }
                if let approved = project.approved {
                    Button("Open approved: \(approved.file.name)") { FileActions.open(approved.file) }
                }
                Button("Show latest in Finder") { FileActions.reveal(project.latest.file) }
                Divider()
                Button("Prepare delivery…") { Delivery.prepare(name: project.name, projects: [project], library: library) }
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: Behaviour (unchanged from before: keys, replay, compare)

    /// Space = Quick Look, ← → = previous / next version. Ignored while typing or moving in the sidebar.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let responder = NSApp.keyWindow?.firstResponder
            if responder is NSText || responder is NSTableView { return event }
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty, comparing == nil else { return event }
            switch event.keyCode {
            case 123: step(-1); return nil
            case 124: step(1); return nil
            case 49: preview = preview == nil ? selected.file.url : nil; return nil
            default: return event
            }
        }
    }

    private func compare(_ file: ProjectFile) {
        let versions = project.versions
        let i = versions.firstIndex { $0.id == (file.exportOf ?? file.id) } ?? 0
        let other = i > 0 ? versions[i - 1] : project.latest
        withAnimation(Motion.standard) { comparing = ComparePair(left: other.id, right: file.id) }
    }

    private func select(_ file: ProjectFile) {
        withAnimation(Motion.standard) { selectedID = file.id }
        focus = FocusRequest(id: file.exportOf ?? file.id)
    }

    private func step(_ delta: Int) {
        let versions = project.versions
        let current = selected.exportOf ?? selected.id
        guard let i = versions.firstIndex(where: { $0.id == current }) else { return }
        let next = min(max(i + delta, 0), versions.count - 1)
        if next != i || selected.isExport { select(versions[next]) }
    }

    private func toggleReplay() {
        if playing {
            playTask?.cancel()
            playing = false
            return
        }
        playing = true
        playTask = Task { @MainActor in
            for version in project.versions {
                if Task.isCancelled { break }
                select(version)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            withAnimation(Motion.standard) { playing = false }
        }
    }
}

// MARK: - Large preview

/// The selected version, as big as the window allows, never cropped.
struct LargePreview: View {
    @Environment(\.palette) private var palette
    let file: ProjectFile
    let version: Int?
    @ViewState private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.surfaceContainerLow)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .transition(.opacity)
                    .id(file.id)
            } else {
                MorphingLoader(size: 40)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let version {
                Text("v\(version)").font(.system(size: 12, weight: .heavy))
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(.regularMaterial, in: Capsule())
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 260)
        .animation(Motion.effects, value: image != nil)
        .task(id: file.id) {
            image = nil
            image = await ThumbnailStore.shared.image(for: file.file.url, side: 1600, modified: file.file.modified)
        }
        .help("Double-click to open · Space for Quick Look")
    }
}

// MARK: - Version filmstrip

struct VersionFilmstrip: View {
    @Environment(\.palette) private var palette
    let project: ProjectGroup
    let versions: [ProjectFile]
    let selectedID: String
    let select: (ProjectFile) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(versions) { v in
                        FilmCard(file: v, number: (project.versions.firstIndex { $0.id == v.id } ?? 0) + 1,
                                 selected: v.id == selectedID || project.exports(of: v).contains { $0.id == selectedID },
                                 isLatest: v.id == project.latest.id)
                            .id(v.id)
                            .onTapGesture { select(v) }
                            .onTapGesture(count: 2) { FileActions.open(v.file) }
                    }
                    if versions.isEmpty {
                        Text("No version matches the search.").foregroundStyle(palette.onSurfaceVariant).padding(30)
                    }
                }
                .padding(.vertical, 4).padding(.horizontal, 2)
            }
            .onChange(of: selectedID) { withAnimation(Motion.gentle) { proxy.scrollTo(selectedID, anchor: .center) } }
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
        }
    }
}

private struct FilmCard: View {
    @Environment(\.palette) private var palette
    let file: ProjectFile
    let number: Int
    let selected: Bool
    let isLatest: Bool
    @ViewState private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                .overlay(Thumbnail(file: file.file, side: 360))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        if selected { Image(systemName: "checkmark") }
                        Text("v\(number)")
                    }
                        .font(.system(size: 10.5, weight: .heavy))
                        .padding(.horizontal, 7).frame(height: 20)
                        .background(selected ? palette.primary : Color.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(selected ? palette.onPrimary : .white)
                        .padding(7)
                }
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.file.name).font(.system(size: 12.5, weight: .bold)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(selected ? palette.primary : palette.onSurface)
                    Text(subtitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                MaterialMenu { VersionMenu(file: file) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).frame(width: 22, height: 18)
                }
                .fixedSize()
                .foregroundStyle(palette.onSurfaceVariant)
            }
        }
        .padding(8)
        .frame(width: 210)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hovering || selected ? palette.surfaceContainerHigh : palette.surfaceContainerLow))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.fast) { hovering = h } }
        .materialContextMenu { VersionMenu(file: file) }
        .help(file.file.path)
    }

    private var subtitle: String {
        var parts = [Format.date(file.file.modified)]
        if let s = file.file.status { parts.append(s.rawValue) } else if isLatest { parts.append("Latest") }
        if file.isRecovered { parts.append("Recovered") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Details panel

/// Pixel size of a file (images, PDFs / Illustrator in points, videos), measured once.
@MainActor
enum FileMetrics {
    private static var cache: [String: String] = [:]

    static func dimensions(of file: CreativeFile) async -> String? {
        let key = file.path + "#\(file.modified.timeIntervalSince1970)"
        if let hit = cache[key] { return hit }
        let url = file.url
        let value: String? = await Task.detached(priority: .utility) { () -> String? in
            switch file.kind {
            case .pdf, .illustrator:
                guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) else { return nil }
                let box = page.getBoxRect(.cropBox)
                return "\(Int(box.width.rounded())) × \(Int(box.height.rounded())) pt"
            case .video:
                let asset = AVURLAsset(url: url)
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let size = try? await track.load(.naturalSize) else { return nil }
                return "\(Int(abs(size.width))) × \(Int(abs(size.height)))"
            default:
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                      let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
                return "\(w) × \(h)"
            }
        }.value
        if let value { cache[key] = value }
        return value
    }
}

struct DetailsPanel: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.versionActions) private var actions
    let project: ProjectGroup
    let file: ProjectFile
    let versions: [ProjectFile]
    @Binding var search: String
    let select: (ProjectFile) -> Void
    let preview: (ProjectFile) -> Void

    @ViewState private var note = ""
    @ViewState private var dimensions: String?

    private var number: Int? { project.versions.firstIndex { $0.id == (file.exportOf ?? file.id) }.map { $0 + 1 } }

    var body: some View {
        VStack(spacing: 12) {
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    infoRows
                    notices
                    approveCard
                    timeline
                }
                .padding(16)
            }
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.surfaceContainerLow))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .scrollFade(height: 30, tinted: false)
        }
        .task(id: file.id) {
            note = library.note(for: file.file)
            dimensions = await FileMetrics.dimensions(of: file.file)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
            TextField("Search in project…", text: $search).textFieldStyle(.plain).font(.system(size: 13.5, weight: .medium))
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
        }
        .foregroundStyle(palette.onSurfaceVariant)
        .padding(.horizontal, 14).frame(height: 42)
        .tonalSurface(Capsule())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(file: file.file, side: 200)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { preview(file) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(file.file.name).font(.system(size: 16, weight: .bold)).foregroundStyle(palette.onSurface)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    MaterialMenu { VersionMenu(file: file) } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).frame(width: 24, height: 20)
                    }
                    .fixedSize()
                    .foregroundStyle(palette.onSurfaceVariant)
                }
                Text("\(file.file.kind.label) · \(Format.size(file.file.size))")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                statusMenu
            }
        }
    }

    private var statusMenu: some View {
        let status = file.file.status
        return MaterialMenu {
            ForEach(VersionStatus.allCases, id: \.self) { s in
                Button { library.setStatus(s, for: file.file) } label: {
                    if status == s { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) }
                }
            }
            Divider()
            Button("No status") { library.setStatus(nil, for: file.file) }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(StatusColor.of(status, palette, scheme)).frame(width: 9, height: 9)
                Text(status?.rawValue ?? "No status").font(.system(size: 12.5, weight: .semibold)).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(StatusColor.of(status, palette, scheme).opacity(0.12)))
            .foregroundStyle(palette.onSurface)
        }
        .fixedSize()
        .help("Saved as a Finder tag")
    }

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("calendar", "Saved", Format.full.string(from: file.file.modified))
            if let dimensions { row("arrow.up.left.and.arrow.down.right", "Dimensions", dimensions) }
            HStack(alignment: .top, spacing: 10) {
                icon("text.alignleft")
                Text("Note").frame(width: 82, alignment: .leading).foregroundStyle(palette.onSurfaceVariant)
                TextField("Add a note", text: $note, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...5)
                    .onChange(of: note) { library.setNote(note, for: file.file) }
            }
            HStack(alignment: .top, spacing: 10) {
                icon("link")
                Text("Source").frame(width: 82, alignment: .leading).foregroundStyle(palette.onSurfaceVariant)
                Button { FileActions.reveal(file.file) } label: {
                    Text(Format.folder(file.file.path).replacingOccurrences(of: "~/", with: "").replacingOccurrences(of: "/", with: " / "))
                        .foregroundStyle(palette.primary).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
            row("point.3.connected.trianglepath.dotted", "Linked by", file.reason.label)
            if let tool = file.file.xmp?.creatorTool { row("paintbrush.pointed", "Made with", tool) }
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(palette.onSurface)
    }

    @ViewBuilder private var notices: some View {
        if file.isRecovered {
            caption("bolt.fill", "Saved by the app after a crash. Same document as the versions around it.", palette.warning)
        }
        if let original = file.duplicateOf {
            caption("plus.square.on.square", "Same bytes as \((original as NSString).lastPathComponent).", palette.onSurfaceVariant)
        }
        if let source = file.exportOf, let parent = project.files.first(where: { $0.id == source }) {
            Button { select(parent) } label: {
                caption("arrow.turn.left.up", "Exported from \(parent.file.name)", palette.primary)
            }
            .buttonStyle(.plain)
        }
    }

    /// "Approve version v2": one click to mark the deliverable.
    @ViewBuilder private var approveCard: some View {
        if !file.isExport, let number {
            let status = file.file.status
            let done = status == .approved || status == .final
            Button {
                library.setStatus(done ? (status == .approved ? .final : nil) : .approved, for: file.file)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: done ? "checkmark.seal.fill" : "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .frame(width: 30, height: 30)
                        .background(StatusColor.approved(palette, scheme), in: Circle())
                        .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                    Text(done ? (status == .approved ? "Approved · mark v\(number) as Final" : "v\(number) is Final · clear") : "Approve version v\(number)")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.onSurfaceVariant)
                }
                .padding(12).frame(minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.surfaceContainer))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline").font(.display(18)).foregroundStyle(palette.onSurface)
                Spacer()
                Text("\(project.versions.count) versions").font(.system(size: 11.5, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
            }
            VStack(alignment: .leading, spacing: 0) {
                let list = Array(versions.reversed())
                ForEach(Array(list.enumerated()), id: \.element.id) { i, v in
                    TimelineEntry(project: project, version: v, isLast: i == list.count - 1,
                                  selected: v.id == file.id || v.id == file.exportOf) { select(v) }
                }
            }
        }
    }

    private func row(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            icon(symbol)
            Text(label).frame(width: 82, alignment: .leading).foregroundStyle(palette.onSurfaceVariant)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.onSurfaceVariant).frame(width: 20)
    }

    private func caption(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(palette.onSurface)
    }
}

/// One line of the vertical timeline: dot, version number, status, date, note.
private struct TimelineEntry: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    let project: ProjectGroup
    let version: ProjectFile
    let isLast: Bool
    let selected: Bool
    let select: () -> Void

    var body: some View {
        let number = (project.versions.firstIndex { $0.id == version.id } ?? 0) + 1
        let status = version.file.status
        let color = StatusColor.of(status, palette, scheme)
        let note = library.note(for: version.file)
        let exports = project.exports(of: version).count
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(status == nil ? palette.outline : color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(selected ? palette.primary : .clear, lineWidth: 3).frame(width: 20, height: 20))
                    .padding(.top, 4)
                if !isLast { Rectangle().fill(palette.outlineVariant).frame(width: 2).frame(maxHeight: .infinity) }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("v\(number)").font(.system(size: 13.5, weight: .heavy)).foregroundStyle(palette.onSurface)
                    if let status {
                        Text(status.rawValue).font(.system(size: 12.5, weight: .bold))
                            .padding(.horizontal, status == .approved || status == .final ? 7 : 0).padding(.vertical, 1)
                            .background(Capsule().fill(status == .approved || status == .final ? color : .clear))
                            .foregroundStyle(status == .approved || status == .final ? (scheme == .dark ? Color.black : Color.white) : color)
                    } else {
                        Text(number == 1 ? "Created" : (version.id == project.latest.id ? "Latest" : version.file.name))
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                    }
                }
                Text(Format.full.string(from: version.file.modified)).font(.system(size: 11.5)).foregroundStyle(palette.onSurfaceVariant)
                if !note.isEmpty {
                    Text(note).font(.system(size: 11.5, weight: .medium)).foregroundStyle(palette.onSurface)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if exports > 0 {
                    Text("\(exports) export\(exports == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(palette.onSurfaceVariant)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .materialContextMenu { VersionMenu(file: version) }
    }
}

/// One colour per status, shared by the dropdown, timeline dots and filmstrip.
enum StatusColor {
    static func approved(_ p: Palette, _ scheme: ColorScheme) -> Color {
        OKLCH(l: scheme == .dark ? 0.78 : 0.55, c: 0.15, h: 145).color
    }

    static func of(_ status: VersionStatus?, _ p: Palette, _ scheme: ColorScheme) -> Color {
        switch status {
        case .approved, .final: return approved(p, scheme)
        case .inReview: return p.warning
        case .sent: return p.primary
        case .draft: return p.onSurfaceVariant
        case nil: return p.outline
        }
    }
}
