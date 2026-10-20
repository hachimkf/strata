import SwiftUI
import QuickLook
import StrataCore

struct ProjectGridView: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    /// Client folders shown first (only on the home view).
    var collections: [Client] = []
    let projects: [ProjectGroup]
    let title: String
    let subtitle: String
    var hero: ProjectGroup? = nil
    @Binding var sort: SortOrder
    let open: (ProjectGroup) -> Void
    var openCollection: (Client) -> Void = { _ in }
    @AppStorage("listMode") private var listMode = false

    private let columns = [GridItem(.adaptive(minimum: 152, maximum: 196), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if hero != nil { AccessCard() }
                if projects.isEmpty && collections.isEmpty {
                    empty
                } else {
                    if let hero {
                        HeroCard(project: hero, open: { open(hero) })
                    }
                    if !collections.isEmpty {
                        section("Clients", "\(collections.count) · everything for one client or brand, in one place")
                        if listMode {
                            VStack(spacing: 4) {
                                ForEach(collections) { c in
                                    CollectionListRow(collection: c) { openCollection(c) }
                                }
                            }
                        } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                                Button { openCollection(collection) } label: { CollectionCard(collection: collection, index: index) }
                                    .buttonStyle(PressScale())
                                    .materialContextMenu {
                                        if let latest = collection.latest { MaterialMenuAction("Open Newest File") { FileActions.open(latest) } }
                                        MaterialMenuAction("Show in Finder") { FileActions.show(collection) }
                                    }
                            }
                        }
                        }
                    }
                    if !projects.isEmpty {
                        if !collections.isEmpty {
                            section("Other projects", "\(projects.count) · not tied to a client")
                        }
                        if listMode {
                            VStack(spacing: 4) {
                                ForEach(projects) { p in ProjectListRow(project: p) { open(p) } }
                            }
                        } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                                Button { open(project) } label: { ProjectCard(project: project, index: index) }
                                    .buttonStyle(PressScale())
                                    .draggable(project.latest.file.url)
                                    .materialContextMenu {
                                        MaterialMenuAction("Open Latest Version") { FileActions.open(project.latest.file) }
                                        MaterialMenuAction("Show Latest in Finder") { FileActions.reveal(project.latest.file) }
                                        MaterialMenuAction("Show in Finder") { FileActions.show(project) }
                                    }
                            }
                        }
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
        }
        .background(palette.surface)
        .scrollFade()
    }

    private func section(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.display(18)).foregroundStyle(palette.onSurface)
            Text(subtitle).font(.system(size: 12.5, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.display(30))
                    .foregroundStyle(palette.onSurface)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer()
            ButtonGroup(items: [(false, "", "square.grid.2x2"), (true, "", "list.bullet")], selection: $listMode, height: 34)
                .help("Grid or list")
            HStack(spacing: 8) {
                ForEach(SortOrder.allCases) { option in
                    FilterChip(title: option.rawValue, selected: sort == option) {
                        withAnimation(Motion.standard) { sort = option }
                    }
                }
            }
        }
    }

    @ViewBuilder private var empty: some View {
        if library.isScanning && library.lastScan == nil {
            VStack(spacing: 18) {
                MorphingLoader(size: 52)
                Text("Reading your folders…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
        } else {
            VStack(spacing: 14) {
                Cookie(lobes: 6, depth: 0.2).fill(palette.secondaryContainer).frame(width: 72, height: 72)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 24, weight: .bold)).foregroundStyle(palette.onSecondaryContainer))
                Text("Nothing here").font(.display(20)).foregroundStyle(palette.onSurface)
                Text("No projects match this view.").foregroundStyle(palette.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
        }
    }
}

// MARK: - Cards

/// A palette grown from a file's artwork (or the app accent, if the user turned artwork colours off).
struct ArtworkPalette: ViewModifier {
    let file: CreativeFile?
    let name: String
    @ViewState private var seed: OKLCH?
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.artworkColorsKey) private var artworkColors = true
    @AppStorage(Prefs.accentKey) private var accent = 0

    func body(content: Content) -> some View {
        let s = artworkColors ? (seed ?? ColorExtractor.fallback(for: name)) : Prefs.accent(accent)
        content
            .environment(\.palette, Palette(seed: s, dark: scheme == .dark))
            .task(id: file?.path ?? name) {
                guard let file else { return }
                let found = await PaletteStore.shared.seed(for: file, name: name)
                withAnimation(Motion.effects) { seed = found }
            }
    }
}

extension View {
    func artworkPalette(_ file: CreativeFile?, name: String) -> some View { modifier(ArtworkPalette(file: file, name: name)) }
}

struct ProjectCard: View {
    let project: ProjectGroup
    let index: Int
    @ViewState private var hovering = false
    @ViewState private var appeared = false

    var body: some View {
        CardBody(project: project, hovering: hovering)
            .scaleEffect(hovering ? 1.015 : 1)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 22)
            .onHover { h in withAnimation(Motion.standard) { hovering = h } }
            .onAppear {
                withAnimation(Motion.standard.delay(min(Double(index) * 0.035, 0.45))) { appeared = true }
            }
    }

    private struct CardBody: View {
        @Environment(\.palette) private var palette
        let project: ProjectGroup
        let hovering: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                VersionStack(versions: Array(project.versions.suffix(3)), fanned: hovering, radius: 14)
                    .overlay(alignment: .bottomLeading) { latestBadge.padding(7) }
                    .padding(.horizontal, 5).padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.display(15))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Format.range(project.first.file.modified, project.latest.file.modified))
                        .font(.system(size: 10.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)

                ViewThatFits(in: .horizontal) {
                    chips(kinds: 2)
                    chips(kinds: 1)
                    chips(kinds: 0)
                }
                .padding(.horizontal, 4).padding(.bottom, 3)
            }
            .padding(8)
            .background(MorphRect(radius: hovering ? 28 : 22).fill(hovering ? palette.surfaceContainerHigh : palette.surfaceContainerLow))
            .contentShape(MorphRect(radius: 22))
        }

        private func chips(kinds: Int) -> some View {
            HStack(spacing: 4) {
                Pill(text: "\(project.versions.count) version\(project.versions.count == 1 ? "" : "s")", fg: palette.onSurfaceVariant, bg: palette.surfaceContainerHigh)
                ForEach(project.extensions.prefix(kinds), id: \.self) { KindPill(ext: $0) }
                if let approved = project.approved, let st = approved.file.status {
                    Pill(text: st.rawValue, fg: palette.surface, bg: palette.tertiary)
                        .help("\(approved.file.name) is marked \(st.rawValue)")
                }
                if project.hasRecovered {
                    Pill(text: "", fg: palette.onWarningContainer, bg: palette.warningContainer, icon: "bolt.fill")
                        .help("Contains a file recovered after a crash")
                }
            }
        }

        private var latestBadge: some View {
            HStack(spacing: 6) {
                Cookie(lobes: 7, depth: 0.2).fill(palette.primary).frame(width: 9, height: 9)
                Text(Format.date(project.latest.file.modified))
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(palette.onSurface)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
        }
    }
}

/// The last few versions as a physical stack of prints; fans out on hover.
struct VersionStack: View {
    @Environment(\.palette) private var palette
    let versions: [ProjectFile]
    var fanned: Bool
    var radius: CGFloat = 18

    var body: some View {
        ZStack {
            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                let depth = versions.count - 1 - index
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay(Thumbnail(file: version.file))
                    .clipShape(MorphRect(radius: fanned ? radius + 6 : radius))
                    .shadow(color: .black.opacity(depth == 0 ? 0.2 : 0.1), radius: depth == 0 ? 10 : 4, y: depth == 0 ? 5 : 2)
                    .rotationEffect(.degrees(angle(depth)), anchor: .bottom)
                    .offset(offset(depth))
                    .scaleEffect(depth == 0 ? 1 : 0.94)
                    .opacity(depth == 0 ? 1 : 0.9)
            }
        }
    }

    private func angle(_ depth: Int) -> Double {
        switch depth { case 0: return 0; case 1: return fanned ? -7 : -2.5; default: return fanned ? 8 : 3 }
    }

    private func offset(_ depth: Int) -> CGSize {
        switch depth {
        case 0: return .zero
        case 1: return fanned ? CGSize(width: -18, height: -10) : CGSize(width: -4, height: -5)
        default: return fanned ? CGSize(width: 20, height: -12) : CGSize(width: 5, height: -7)
        }
    }
}

/// The project you touched last, big: one click to its newest file.
struct HeroCard: View {
    let project: ProjectGroup
    let open: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Content(project: project, hovering: hovering, open: open)
            .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
    }

    private struct Content: View {
        @Environment(\.palette) private var palette
        let project: ProjectGroup
        let hovering: Bool
        let open: () -> Void

        var body: some View {
            HStack(alignment: .center, spacing: 20) {
                VersionStack(versions: Array(project.versions.suffix(3)), fanned: hovering, radius: 20)
                    .frame(maxWidth: 160)
                    .padding(.vertical, 8)
                    .onTapGesture(perform: open)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Continue working")
                        .font(.system(size: 11.5, weight: .heavy))
                                                .foregroundStyle(palette.onSurfaceVariant)
                    Text(project.name)
                        .font(.display(24))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(2)
                    Text("Latest saved \(Format.ago(project.latest.file.modified)) · \(project.latest.file.name)")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 10) {
                        Button { FileActions.open(project.latest.file) } label: {
                            Label("Open latest", systemImage: "arrow.up.forward")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 16).frame(height: 38)
                                .background(palette.primary, in: Capsule())
                                .foregroundStyle(palette.onPrimary)
                        }
                        .buttonStyle(PressScale())
                        Button(action: open) {
                            Label("See the timeline", systemImage: "point.3.filled.connected.trianglepath.dotted")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 16).frame(height: 38)
                                .background(palette.surfaceContainerHigh, in: Capsule())
                                .foregroundStyle(palette.onSurface)
                        }
                        .buttonStyle(PressScale())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.surfaceContainerLow))
        }
    }
}

struct FilterChip: View {
    @Environment(\.palette) private var palette
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).transition(.scale.combined(with: .opacity)) }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).frame(height: 34)
            .background(Capsule().fill(selected ? palette.surfaceContainerHighest : .clear))
            .foregroundStyle(selected ? palette.onSecondaryContainer : palette.onSurfaceVariant)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
    }
}

/// M3 Expressive loading indicator: a rotating, breathing cookie.
struct SpinningCookie: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 40
    @ViewState private var spin = false

    var body: some View {
        Cookie(lobes: 9, depth: spin ? 0.22 : 0.08)
            .fill(palette.primary)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

// MARK: - Loose files

struct LooseFilesView: View {
    @Environment(\.palette) private var palette
    let files: [CreativeFile]
    @ViewState private var preview: URL?
    @ViewState private var selectedFile: String?
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Loose files").font(.display(30)).foregroundStyle(palette.onSurface)
                    Text("\(files.count.formatted()) files with no other version found · click to select, Space to preview, double-click to open")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(files.prefix(600)) { file in
                        VStack(alignment: .leading, spacing: 8) {
                            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                                .overlay(Thumbnail(file: file, side: 220))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    .foregroundStyle(palette.onSurface)
                                Text("\(Format.date(file.modified)) · \(Format.shortFolder(file.path))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                            }
                            .padding(.horizontal, 4)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selectedFile == file.path ? palette.secondaryContainer : palette.surfaceContainer))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(selectedFile == file.path ? palette.primary : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { FileActions.open(file) }
                        .simultaneousGesture(TapGesture().onEnded { selectedFile = file.path })
                        .materialContextMenu {
                            MaterialMenuAction("Open") { FileActions.open(file) }
                            MaterialMenuAction("Show in Finder") { FileActions.reveal(file) }
                        }
                    }
                }
                if files.count > 600 {
                    Text("Showing the 600 most recent. Use search to find older files.").foregroundStyle(palette.onSurfaceVariant)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
        }
        .background(palette.surface)
        .scrollFade()
        .quickLookPreview($preview)
        .spaceToQuickLook(selectedFile.map { URL(fileURLWithPath: $0) }, preview: $preview)
    }
}

// MARK: - Dense list rows

/// One line per client: for managing many at once.
struct CollectionListRow: View {
    @Environment(\.palette) private var palette
    let collection: Client
    let open: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                ShapeAvatar(file: collection.latest, name: collection.name, size: 34)
                Text(collection.name).font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.onSurface).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(collection.projects.count) projects").frame(width: 90, alignment: .trailing)
                Text("\(collection.fileCount) files").frame(width: 80, alignment: .trailing)
                Text(Format.date(collection.lastModified)).frame(width: 110, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .medium)).monospacedDigit()
            .foregroundStyle(palette.onSurfaceVariant)
            .padding(.horizontal, 12).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? palette.surfaceContainerHigh : palette.surfaceContainerLow))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .materialContextMenu {
            if let latest = collection.latest { MaterialMenuAction("Open Newest File") { FileActions.open(latest) } }
            MaterialMenuAction("Show in Finder") { FileActions.show(collection) }
        }
    }
}

/// One line per project: name, client, versions, latest date and status.
struct ProjectListRow: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    let project: ProjectGroup
    let open: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Thumbnail(file: project.latest.file, side: 96)
                    .frame(width: 44, height: 33)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.onSurface).lineLimit(1)
                    Text(library.collection(containing: project.id)?.name ?? "No client")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let status = project.latest.file.status {
                    Pill(text: status.rawValue, fg: palette.onTertiaryContainer, bg: palette.tertiaryContainer)
                }
                ForEach(project.extensions.prefix(2), id: \.self) { KindPill(ext: $0) }
                Text("\(project.versions.count) version\(project.versions.count == 1 ? "" : "s")").frame(width: 80, alignment: .trailing)
                Text(Format.date(project.latest.file.modified)).frame(width: 110, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .medium)).monospacedDigit()
            .foregroundStyle(palette.onSurfaceVariant)
            .padding(.horizontal, 12).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? palette.surfaceContainerHigh : palette.surfaceContainerLow))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .draggable(project.latest.file.url)
        .materialContextMenu {
            MaterialMenuAction("Open Latest Version") { FileActions.open(project.latest.file) }
            MaterialMenuAction("Show in Finder") { FileActions.show(project) }
        }
    }
}
