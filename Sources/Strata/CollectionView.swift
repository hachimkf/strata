import SwiftUI
import QuickLook
import StrataCore

typealias Client = StrataCore.Collection

/// A client shown as a folder: the newest artwork from its different projects peeking out.
struct CollectionCard: View {
    let collection: Client
    let index: Int
    @ViewState private var hovering = false
    @ViewState private var appeared = false

    var body: some View {
        Face(collection: collection, hovering: hovering)
            .artworkPalette(collection.latest, name: collection.name)
            .scaleEffect(hovering ? 1.015 : 1)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 22)
            .onHover { h in withAnimation(Motion.standard) { hovering = h } }
            .onAppear { withAnimation(Motion.standard.delay(min(Double(index) * 0.035, 0.45))) { appeared = true } }
    }

    private struct Face: View {
        @Environment(\.palette) private var palette
        let collection: Client
        let hovering: Bool

        /// One cover per project (newest first), so the folder shows the client's range of work.
        private var covers: [CreativeFile] {
            var seen = Set<String>()
            var out: [CreativeFile] = []
            for p in collection.projects where out.count < 3 {
                if seen.insert(p.id).inserted { out.append(p.latest.file) }
            }
            for f in collection.singles where out.count < 3 { out.append(f) }
            return Array(out.reversed())
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .topLeading) {
                    // Folder tab
                    UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous)
                        .fill(palette.primary)
                        .frame(width: 58, height: 14)
                        .offset(x: 12, y: -8)
                    FileStack(files: covers, fanned: hovering)
                        .padding(8)
                        .background(MorphRect(radius: 16).fill(palette.primaryContainer))
                }
                .padding(.top, 10).padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(collection.name)
                        .font(.display(16))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(collection.projects.count) projects · \(collection.fileCount) files")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Pill(text: Format.date(collection.lastModified), fg: palette.onPrimary, bg: palette.primary, icon: "clock.fill")
                        ForEach(collection.extensions.prefix(2), id: \.self) { KindPill(ext: $0) }
                    }
                    HStack(spacing: 4) {
                        Pill(text: Format.date(collection.lastModified), fg: palette.onPrimary, bg: palette.primary, icon: "clock.fill")
                        if let ext = collection.extensions.first { KindPill(ext: ext) }
                    }
                    Pill(text: Format.date(collection.lastModified), fg: palette.onPrimary, bg: palette.primary, icon: "clock.fill")
                }
                .padding(.horizontal, 4).padding(.bottom, 3)
            }
            .padding(8)
            .background(MorphRect(radius: hovering ? 28 : 22).fill(hovering ? palette.surfaceContainerHigh : palette.surfaceContainerLow))
            .contentShape(MorphRect(radius: 22))
        }
    }
}

/// Like `VersionStack`, but for arbitrary files.
struct FileStack: View {
    let files: [CreativeFile]
    var fanned: Bool

    var body: some View {
        ZStack {
            ForEach(Array(files.enumerated()), id: \.element.path) { index, file in
                let depth = files.count - 1 - index
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay(Thumbnail(file: file))
                    .clipShape(MorphRect(radius: fanned ? 14 : 10))
                    .shadow(color: .black.opacity(depth == 0 ? 0.22 : 0.1), radius: depth == 0 ? 8 : 3, y: 3)
                    .rotationEffect(.degrees(depth == 0 ? 0 : (depth == 1 ? (fanned ? -8 : -3) : (fanned ? 9 : 3.5))), anchor: .bottom)
                    .offset(x: depth == 0 ? 0 : (depth == 1 ? (fanned ? -16 : -4) : (fanned ? 18 : 5)),
                            y: depth == 0 ? 0 : (fanned ? -12 : -5))
                    .scaleEffect(depth == 0 ? 1 : 0.93)
            }
        }
    }
}

enum ClientTab: String, CaseIterable { case projects = "Projects", brand = "Brand kit", activity = "Activity" }

/// A client's page: projects and other files, the brand kit, and activity.
struct CollectionPage: View {
    let collection: Client
    let backTitle: String
    let onBack: () -> Void
    let openProject: (ProjectGroup) -> Void

    var body: some View {
        Content(collection: collection, backTitle: backTitle, onBack: onBack, openProject: openProject)
            .artworkPalette(collection.latest, name: collection.name)
    }

    private struct Content: View {
        @EnvironmentObject var library: Library
        @Environment(\.palette) private var palette
        let collection: Client
        let backTitle: String
        let onBack: () -> Void
        let openProject: (ProjectGroup) -> Void
        @ViewState private var preview: URL?
        @ViewState private var selectedFile: String?
        @ViewState private var tab: ClientTab = .projects
        @ViewState private var renaming = false
        @ViewState private var merging = false
        @ViewState private var confirmHide = false
        @AppStorage("listMode") private var listMode = false

        private let columns = [GridItem(.adaptive(minimum: 152, maximum: 196), spacing: 14, alignment: .top)]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    HStack {
                        ButtonGroup(items: ClientTab.allCases.map { ($0, $0.rawValue, symbol($0)) }, selection: $tab, height: 40)
                        Spacer()
                        if tab == .projects {
                            ButtonGroup(items: [(false, "", "square.grid.2x2"), (true, "", "list.bullet")], selection: $listMode, height: 34)
                                .help("Grid or list")
                        }
                    }
                    switch tab {
                    case .projects: projectsTab
                    case .brand: BrandKitView(collection: collection)
                    case .activity: ActivityView(collection: collection)
                    }
                }
                .padding(.horizontal, 32).padding(.vertical, 22)
                .animation(Motion.standard, value: tab)
            }
            .background(palette.surface)
        .scrollFade()
            .overlay(alignment: .topLeading) {
                FloatingBack(title: backTitle, action: onBack).padding(.leading, 26).padding(.top, 18)
            }
            .quickLookPreview($preview)
            .spaceToQuickLook(selectedFile.map { URL(fileURLWithPath: $0) }, preview: $preview)
            .sheet(isPresented: $renaming) {
                NamePrompt(title: "Rename client", initial: collection.name) { library.rename(collection, to: $0) }
            }
            .sheet(isPresented: $merging) {
                PickerSheet(title: "Merge \(collection.name) into…",
                            items: library.collections.filter { $0.id != collection.id }.map {
                                PickItem(id: $0.id, title: $0.name, subtitle: "\($0.projects.count) projects · \($0.fileCount) files", file: $0.latest)
                            }) { item in
                    if let target = library.collection(id: item.id) { library.mergeClients(collection, into: target) }
                }
            }
            .confirmationDialog("Hide \(collection.name)?", isPresented: $confirmHide) {
                Button("Hide") { library.hide(collection); onBack() }
            } message: {
                Text("It disappears from Your work. Bring it back any time in Settings › Clients.")
            }
        }

        private func symbol(_ t: ClientTab) -> String {
            switch t {
            case .projects: return "square.stack.3d.up.fill"
            case .brand: return "paintpalette.fill"
            case .activity: return "chart.bar.fill"
            }
        }

        @ViewBuilder private var projectsTab: some View {
            if !collection.projects.isEmpty {
                section("Projects", "\(collection.projects.count) with versions, newest first")
                if listMode {
                    VStack(spacing: 4) { ForEach(collection.projects) { p in ProjectListRow(project: p) { openProject(p) } } }
                } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(Array(collection.projects.enumerated()), id: \.element.id) { i, project in
                        Button { openProject(project) } label: { ProjectCard(project: project, index: i) }
                            .buttonStyle(PressScale())
                            .draggable(project.latest.file.url)
                            .materialContextMenu {
                                Button("Open Latest Version") { FileActions.open(project.latest.file) }
                                Button("Show in Finder") { FileActions.show(project) }
                                Divider()
                                Button("Remove from \(collection.name)") { library.removeFromClient(project) }
                            }
                    }
                }
            }
            }
            if !collection.singles.isEmpty {
                section("Other files", "\(collection.singles.count) files with a single version")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(collection.singles) { file in
                        FileTile(file: file, selected: selectedFile == file.path) { selectedFile = file.path }
                            .draggable(file.url)
                    }
                }
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 10) {
                Color.clear.frame(height: 34)   // room for the floating back button

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 18) { clientTitle; Spacer(minLength: 12); clientActions.fixedSize() }
                    VStack(alignment: .leading, spacing: 14) { clientTitle; clientActions.fixedSize() }
                }
            }
        }

        private var clientTitle: some View {
            HStack(alignment: .bottom, spacing: 18) {
                ShapeAvatar(file: collection.latest, name: collection.name, size: 92)
                VStack(alignment: .leading, spacing: 8) {
                    Text("CLIENT  ·  \(collection.projects.count) PROJECTS  ·  \(collection.fileCount) FILES")
                        .font(.system(size: 11.5, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                    Text(collection.name)
                        .font(.display(46))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(Format.range(collection.firstModified, collection.lastModified))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
        }

        private var clientActions: some View {
            HStack(spacing: 10) {
                MaterialMenu {
                    Button(library.isFavorite(collection) ? "Remove from Favorites" : "Add to Favorites") { library.toggleFavorite(collection) }
                    Button("Rename…") { renaming = true }
                    Button("Merge into another client…") { merging = true }
                    Button("Show in Finder") { FileActions.show(collection) }
                    Divider()
                    Button("Hide this client…") { confirmHide = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(palette.secondaryContainer, in: Circle())
                        .foregroundStyle(palette.onSecondaryContainer)
                }
                .fixedSize()
                if let latest = collection.latest {
                    SplitButton(title: "Open newest", symbol: "arrow.up.forward", action: { FileActions.open(latest) }) {
                        Button("Open \(latest.name)") { FileActions.open(latest) }
                        Button("Show in Finder") { FileActions.reveal(latest) }
                        Divider()
                        Button("Prepare delivery for \(collection.name)…") {
                            Delivery.prepare(name: collection.name, projects: collection.projects, library: library)
                        }
                    }
                    .help(latest.name)
                }
            }
        }

        private func section(_ title: String, _ subtitle: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.display(22)).foregroundStyle(palette.onSurface)
                Text(subtitle).font(.system(size: 12.5, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
            }
        }
    }
}

/// A single file: thumbnail, name, date. Click to preview, double-click to open.
/// Click to select (Space previews it), double-click to open, like Finder.
struct FileTile: View {
    @Environment(\.palette) private var palette
    let file: CreativeFile
    var selected = false
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                .overlay(Thumbnail(file: file, side: 220))
                .overlay(alignment: .topTrailing) { KindPill(ext: file.fileExtension).padding(6) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(palette.onSurface)
                Text("\(Format.date(file.modified)) · \(Format.shortFolder(file.path))")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(selected ? palette.secondaryContainer : palette.surfaceContainer))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? palette.primary : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FileActions.open(file) }
        .simultaneousGesture(TapGesture().onEnded(select))
        .materialContextMenu {
            Button("Open") { FileActions.open(file) }
            Button("Show in Finder") { FileActions.reveal(file) }
        }
        .help(file.path)
    }
}
