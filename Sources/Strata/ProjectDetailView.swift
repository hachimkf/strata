import SwiftUI
import QuickLook
import StrataCore

/// One project as a timeline: first version on the left, latest on the right, exports hanging below.
struct ProjectDetailView: View {
    let project: ProjectGroup
    @ViewState private var selectedID: String?
    @ViewState private var preview: URL?

    private var selected: ProjectFile {
        project.files.first { $0.id == selectedID } ?? project.latest
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 28).padding(.top, 20)
                timeline
                legend.padding(.horizontal, 28)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            InspectorPane(project: project, file: selected, select: { selectedID = $0.id }, preview: { preview = $0.file.url })
                .frame(width: 300)
        }
        .navigationTitle(project.name)
        .quickLookPreview($preview)
        .background {
            // Space bar = Quick Look, like Finder.
            Button("") { preview = preview == nil ? selected.file.url : nil }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name).font(.system(size: 36, weight: .regular, design: .serif)).lineLimit(1)
                Spacer()
                Button { FileActions.reveal(project.files.map(\.file)) } label: {
                    Label("Show All in Finder", systemImage: "folder")
                }
                .controlSize(.large)
                Button {
                    selectedID = project.latest.id
                    FileActions.open(project.latest.file)
                } label: {
                    Label("Open Latest", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
            Text(summary).foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let v = project.versions.count
        let e = project.files.count - v
        var parts = ["\(v) version\(v == 1 ? "" : "s")"]
        if e > 0 { parts.append("\(e) export\(e == 1 ? "" : "s")") }
        parts.append("\(Format.dayYear.string(from: project.first.file.modified)) → \(Format.dayYear.string(from: project.latest.file.modified))")
        let folders = Set(project.files.map { $0.file.folder }).count
        if folders > 1 { parts.append("spread across \(folders) folders") }
        return parts.joined(separator: " · ")
    }

    private var timeline: some View {
        let versions = project.versions
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        VersionNode(
                            version: version,
                            exports: project.exports(of: version),
                            isFirst: index == 0,
                            isLast: index == versions.count - 1,
                            gap: index == 0 ? nil : Format.gap(from: versions[index - 1].file.modified, to: version.file.modified),
                            selectedID: selectedID ?? project.latest.id,
                            select: { selectedID = $0.id },
                            open: { FileActions.open($0.file) }
                        )
                        .id(version.id)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
            }
            .onAppear { proxy.scrollTo(project.latest.id, anchor: .trailing) }
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            legendItem(Circle().fill(Color.primary), "First version")
            legendItem(Circle().fill(Color.accentColor), "Latest version")
            legendItem(Circle().fill(Color.orange), "Recovered after a crash")
            legendItem(Rectangle().fill(Color.secondary).frame(width: 12, height: 2), "Export (PDF, PNG…)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 16)
    }

    private func legendItem<S: View>(_ swatch: S, _ text: String) -> some View {
        HStack(spacing: 6) { swatch.frame(width: 9, height: 9); Text(text) }
    }
}

struct VersionNode: View {
    let version: ProjectFile
    let exports: [ProjectFile]
    let isFirst: Bool
    let isLast: Bool
    let gap: String?
    let selectedID: String
    let select: (ProjectFile) -> Void
    let open: (ProjectFile) -> Void

    @ViewState private var hovering = false
    private let width: CGFloat = 196

    var body: some View {
        VStack(spacing: 0) {
            card
            rail
            badges.frame(minHeight: 24)
            if !exports.isEmpty { exportList }
        }
        .frame(width: width)
    }

    private var isSelected: Bool { selectedID == version.id }

    private var card: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                .overlay(Thumbnail(file: version.file))
                .overlay(alignment: .topTrailing) {
                    KindChip(text: version.file.fileExtension, color: .primary)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(version.file.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Text("\(Format.date(version.file.modified)) · \(Format.shortFolder(version.file.path))")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(width: width - 22)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(hovering || isSelected ? 0.12 : 0.04), radius: hovering ? 12 : 6, y: hovering ? 6 : 2)
        .offset(y: hovering ? -3 : 0)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hovering = h } }
        .onTapGesture(count: 2) { open(version) }
        .onTapGesture { select(version) }
        .contextMenu {
            Button("Open") { FileActions.open(version.file) }
            Button("Show in Finder") { FileActions.reveal(version.file) }
        }
        .help(version.file.path)
    }

    private var rail: some View {
        ZStack {
            HStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : Color.secondary.opacity(0.35)).frame(height: 2)
                Rectangle().fill(isLast ? .clear : Color.secondary.opacity(0.35)).frame(height: 2)
            }
            if isLast {
                HStack(spacing: 0) {
                    LinearGradient(colors: [Color.secondary.opacity(0.35), .accentColor], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 2)
                    Color.clear
                }
            }
            dot
            if let gap {
                Text(gap)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
                    .fixedSize()
                    .position(x: 0, y: 22)
            }
        }
        .frame(width: width, height: 44)
    }

    @ViewBuilder private var dot: some View {
        if isLast {
            Circle().fill(Color.accentColor).frame(width: 14, height: 14)
                .shadow(color: .accentColor.opacity(0.7), radius: 8)
                .overlay(Circle().stroke(Color.accentColor.opacity(0.25), lineWidth: 6).frame(width: 22, height: 22))
        } else if isFirst {
            Circle().fill(Color.primary).frame(width: 14, height: 14)
        } else if version.isRecovered {
            Circle().fill(Color.orange).frame(width: 14, height: 14)
        } else {
            Circle().strokeBorder(Color.secondary, lineWidth: 2)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                .frame(width: 14, height: 14)
        }
    }

    private var badges: some View {
        HStack(spacing: 5) {
            if isFirst { KindChip(text: "Origin", color: .primary) }
            if isLast { KindChip(text: "Latest", color: .accentColor) }
            if version.isRecovered { KindChip(text: "Recovered", color: .orange) }
            if version.isDuplicate { KindChip(text: "Duplicate", color: .gray) }
        }
    }

    private var exportList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 1.5, height: 14)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(exports.prefix(5)) { export in
                    HStack(spacing: 7) {
                        Thumbnail(file: export.file, side: 64)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(export.file.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedID == export.id ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { open(export) }
                    .onTapGesture { select(export) }
                }
                if exports.count > 5 {
                    Text("+\(exports.count - 5) more exports").font(.system(size: 10.5)).foregroundStyle(.secondary).padding(.leading, 5)
                }
            }
            .frame(width: width - 22)
        }
    }
}

struct InspectorPane: View {
    let project: ProjectGroup
    let file: ProjectFile
    let select: (ProjectFile) -> Void
    let preview: (ProjectFile) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                    .overlay(Thumbnail(file: file.file, side: 600))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    .onTapGesture { preview(file) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.file.name).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                    Text(position).font(.system(size: 12)).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button { FileActions.open(file.file) } label: { Text("Open").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    Button { preview(file) } label: { Image(systemName: "eye") }.help("Quick Look (Space)")
                    Button { FileActions.reveal(file.file) } label: { Image(systemName: "folder") }.help("Show in Finder")
                }
                .controlSize(.large)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    row("Saved", Format.full.string(from: file.file.modified))
                    row("Created", Format.full.string(from: file.file.created))
                    row("Kind", "\(file.file.kind.label) · \(file.file.fileExtension)")
                    row("Size", Format.size(file.file.size))
                    row("Where", Format.folder(file.file.path))
                    row("Linked by", file.reason.label)
                    if let tool = file.file.xmp?.creatorTool { row("Made with", tool) }
                }
                .font(.system(size: 12))

                if file.isRecovered {
                    note("Saved by the app after a crash. It belongs to the same document as the versions around it.", .orange)
                }
                if let original = file.duplicateOf {
                    note("Exact copy of \((original as NSString).lastPathComponent). Safe to delete one of them.", .gray)
                }
                if file.id == project.latest.id {
                    note("This is the newest version of the project.", .accentColor)
                }
                if let source = file.exportOf, let parent = project.files.first(where: { $0.id == source }) {
                    Button { select(parent) } label: {
                        Label("Exported from \(parent.file.name)", systemImage: "arrow.turn.left.up")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
    }

    private var position: String {
        if file.isExport { return "Export" }
        let index = (project.versions.firstIndex { $0.id == file.id } ?? 0) + 1
        return "Version \(index) of \(project.versions.count)"
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.3)))
    }
}
