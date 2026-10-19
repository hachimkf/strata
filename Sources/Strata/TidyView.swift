import SwiftUI
import QuickLook
import StrataCore

/// Exact duplicates and old crash copies, ready to move to the Trash after you confirm.
/// Strata never deletes anything itself: files go to the Trash, where you can put them back.
struct TidyView: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    @ViewState private var chosen: Set<String> = []
    @ViewState private var confirming = false
    @ViewState private var preview: URL?
    @ViewState private var primed = false

    struct Candidate: Identifiable {
        let file: CreativeFile
        let project: ProjectGroup
        let reason: String
        let keep: String
        let keepPath: String
        var id: String { file.path }
    }

    /// Later copies of an identical file (the oldest one is kept).
    private var duplicates: [Candidate] {
        library.projects.flatMap { p in
            p.files.compactMap { f in
                guard let original = f.duplicateOf else { return nil }
                return Candidate(file: f.file, project: p, reason: "Identical to another file",
                                 keep: "Same bytes as the kept file", keepPath: original)
            }
        }
    }

    /// Crash copies that a newer, normal save has already replaced.
    private var oldRecoveries: [Candidate] {
        library.projects.flatMap { p in
            p.versions.compactMap { v in
                guard v.isRecovered, v.id != p.latest.id,
                      let newer = p.versions.first(where: { $0.file.modified > v.file.modified && !$0.isRecovered }) else { return nil }
                return Candidate(file: v.file, project: p, reason: "Recovered after a crash, replaced later",
                                 keep: "A newer normal save exists", keepPath: newer.file.path)
            }
        }
    }

    var body: some View {
        let dups = duplicates, recs = oldRecoveries
        let all = dups + recs
        let selected = all.filter { chosen.contains($0.id) }
        let bytes = selected.reduce(Int64(0)) { $0 + $1.file.size }

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tidy up").font(.display(44)).foregroundStyle(palette.onSurface)
                    Text("Copies you might not need. Identical files can be intentional (a delivered folder, a backup), so nothing is selected until you choose. Chosen files go to the Trash, where you can put them back.")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                }
                HStack(spacing: 12) {
                    stat(Format.size(dups.reduce(0) { $0 + $1.file.size }), "\(dups.count) exact duplicates")
                    stat(Format.size(recs.reduce(0) { $0 + $1.file.size }), "\(recs.count) old crash copies")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(selected.count) selected · \(Format.size(bytes))")
                            .font(.system(size: 15, weight: .heavy)).foregroundStyle(palette.onPrimaryContainer)
                        Button { confirming = true } label: {
                            Label("Move to Trash", systemImage: "trash.fill")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 20).frame(height: 44)
                                .background(palette.primary, in: Capsule())
                                .foregroundStyle(palette.onPrimary)
                        }
                        .buttonStyle(PressScale())
                        .disabled(selected.isEmpty)
                        .opacity(selected.isEmpty ? 0.5 : 1)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MorphRect(radius: 26).fill(palette.primaryContainer))
                }
                if all.isEmpty {
                    VStack(spacing: 14) {
                        MorphShape(from: .flower, to: .flower, progress: 0).fill(palette.primaryContainer).frame(width: 80, height: 80)
                            .overlay(Image(systemName: "sparkles").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.onPrimaryContainer))
                        Text("All tidy").font(.display(20))
                        Text("No duplicates or leftover crash copies.").foregroundStyle(palette.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
                if !dups.isEmpty { group("Identical copies", "Same bytes as another file", dups) }
                if !recs.isEmpty { group("Old crash copies", "A newer normal save exists", recs) }
            }
            .padding(.horizontal, 32).padding(.vertical, 28)
        }
        .background(palette.surface)
        .scrollFade()
        .quickLookPreview($preview)
        .onAppear { primed = true }
        .confirmationDialog("Move \(selected.count) files to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) {
                library.trash(selected.map(\.file))
                chosen.subtract(selected.map(\.id))
            }
        } message: {
            Text("\(Format.size(bytes)) · you can put them back from the Trash.")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.display(28)).foregroundStyle(palette.onTertiaryContainer)
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.onTertiaryContainer.opacity(0.8))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MorphRect(radius: 26).fill(palette.tertiaryContainer))
    }

    private func group(_ title: String, _ subtitle: String, _ items: [Candidate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.display(20)).foregroundStyle(palette.onSurface)
                Text(subtitle).font(.system(size: 12.5, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                Button("Select all") { chosen.formUnion(items.map(\.id)) }.buttonStyle(.link)
                Button("None") { chosen.subtract(items.map(\.id)) }.buttonStyle(.link)
            }
            VStack(spacing: 6) {
                ForEach(items) { c in row(c) }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.surfaceContainerLow))
    }

    /// The file that stays, beside the copy that could go, with both locations.
    private func row(_ c: Candidate) -> some View {
        let on = chosen.contains(c.id)
        return HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? palette.primary : palette.outline)
            side(label: "MOVE TO TRASH?", path: c.file.path, file: c.file, emphasis: on)
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.outline)
            side(label: "KEEP", path: c.keepPath, file: library.file(at: c.keepPath), emphasis: false)
            Text(Format.size(c.file.size)).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.onSurfaceVariant)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: on ? 20 : 12, style: .continuous).fill(on ? palette.secondaryContainer : .clear))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.fast) { if on { chosen.remove(c.id) } else { chosen.insert(c.id) } } }
        .help("\(c.project.name) · \(c.keep)")
        .materialContextMenu {
            Button("Show copy in Finder") { FileActions.reveal(c.file) }
            Button("Show kept file in Finder") { FileActions.reveal(path: c.keepPath) }
            Button("Quick Look") { preview = c.file.url }
        }
    }

    private func side(label: String, path: String, file: CreativeFile?, emphasis: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let file { Thumbnail(file: file, side: 80) } else { Rectangle().fill(palette.surfaceContainerHighest) }
            }
            .frame(width: 44, height: 33)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture { preview = URL(fileURLWithPath: path) }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 9.5, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(emphasis ? palette.primary : palette.onSurfaceVariant)
                Text((path as NSString).lastPathComponent).font(.system(size: 12.5, weight: .bold)).lineLimit(1).truncationMode(.middle)
                Text(Format.folder(path)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(1).truncationMode(.head)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
