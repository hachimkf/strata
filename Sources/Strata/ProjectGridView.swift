import SwiftUI
import QuickLook
import StrataCore

struct ProjectGridView: View {
    @EnvironmentObject var library: Library
    let projects: [ProjectGroup]
    let title: String
    let subtitle: String
    let open: (ProjectGroup) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 34, weight: .semibold, design: .serif))
                    Text(projects.isEmpty ? subtitle : "\(projects.count) projects · \(subtitle.lowercased())")
                        .foregroundStyle(.secondary)
                }
                if projects.isEmpty {
                    empty
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                        ForEach(projects) { project in
                            Button { open(project) } label: { ProjectCard(project: project) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Open Latest Version") { FileActions.open(project.latest.file) }
                                    Button("Show Latest in Finder") { FileActions.reveal(project.latest.file) }
                                    Button("Show All Files in Finder") { FileActions.reveal(project.files.map(\.file)) }
                                }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    @ViewBuilder private var empty: some View {
        if library.isScanning && library.lastScan == nil {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading your folders…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            ContentUnavailableView("Nothing here", systemImage: "square.stack.3d.up.slash",
                                   description: Text("No projects match this view."))
                .frame(minHeight: 300)
        }
    }
}

/// A project shown as a little stack of its latest versions.
struct ProjectCard: View {
    let project: ProjectGroup
    @ViewState private var hovering = false

    var body: some View {
        let versions = project.versions
        let layers = Array(versions.suffix(3))
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                ForEach(Array(layers.enumerated()), id: \.element.id) { index, version in
                    let depth = layers.count - 1 - index   // 0 = top card
                    Color.clear
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .overlay(Thumbnail(file: version.file))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.08)))
                        .shadow(color: .black.opacity(depth == 0 ? 0.18 : 0.08), radius: depth == 0 ? 8 : 3, y: depth == 0 ? 4 : 1)
                        .rotationEffect(.degrees(rotation(depth)))
                        .offset(x: offset(depth).width, y: offset(depth).height)
                        .opacity(depth == 0 ? 1 : (depth == 1 ? 0.85 : 0.6))
                }
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 5) {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            Text("Latest · \(Format.date(project.latest.file.modified))")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .padding(.horizontal, 8).padding(.top, 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text("\(versions.count) version\(versions.count == 1 ? "" : "s") · since \(Format.date(project.first.file.modified))")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 5) {
                ForEach(project.extensions.prefix(4), id: \.self) { KindChip(text: $0) }
                if project.hasRecovered { KindChip(text: "Recovered", color: .orange) }
                if project.duplicateCount > 0 { KindChip(text: "\(project.duplicateCount) dup", color: .gray) }
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hovering ? Color(nsColor: .controlBackgroundColor) : .clear)
                .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 12, y: 6)
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(duration: 0.35)) { hovering = h } }
    }

    private func rotation(_ depth: Int) -> Double {
        switch depth { case 0: return 0; case 1: return hovering ? -5 : -2; default: return hovering ? 6 : 3 }
    }

    private func offset(_ depth: Int) -> CGSize {
        switch depth {
        case 0: return .zero
        case 1: return hovering ? CGSize(width: -10, height: -6) : CGSize(width: -3, height: -3)
        default: return hovering ? CGSize(width: 12, height: -8) : CGSize(width: 4, height: -4)
        }
    }
}

/// Files that didn't match anything, newest first.
struct LooseFilesView: View {
    let files: [CreativeFile]
    @ViewState private var preview: URL?
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Loose Files").font(.system(size: 34, weight: .semibold, design: .serif))
                    Text("\(files.count.formatted()) files with no other version found · click to preview, double-click to open")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(files.prefix(600)) { file in
                        VStack(alignment: .leading, spacing: 6) {
                            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                                .overlay(Thumbnail(file: file, side: 220))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(file.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                            Text("\(Format.date(file.modified)) · \(Format.shortFolder(file.path))")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { FileActions.open(file) }
                        .onTapGesture { preview = file.url }
                        .contextMenu {
                            Button("Open") { FileActions.open(file) }
                            Button("Show in Finder") { FileActions.reveal(file) }
                        }
                    }
                }
                if files.count > 600 {
                    Text("Showing the 600 most recent. Use search to find older files.").foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .quickLookPreview($preview)
    }
}
