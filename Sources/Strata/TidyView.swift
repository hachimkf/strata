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
        var id: String { file.path }
    }

    /// Later copies of an identical file (the oldest one is kept).
    private var duplicates: [Candidate] {
        library.projects.flatMap { p in
            p.files.compactMap { f in
                guard let original = f.duplicateOf else { return nil }
                return Candidate(file: f.file, project: p, reason: "Identical to another file",
                                 keep: "Keeps \((original as NSString).lastPathComponent) in \(Format.shortFolder(original))")
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
                                 keep: "Newer: \(newer.file.name), \(Format.date(newer.file.modified))")
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
                    Text("Files you can safely let go. Nothing is deleted: they go to the Trash, where you can put them back.")
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
                if !dups.isEmpty { group("Exact duplicates", "Selected by default: same bytes as another file", dups) }
                if !recs.isEmpty { group("Old crash copies", "Not selected by default: check them first", recs) }
            }
            .padding(.horizontal, 32).padding(.vertical, 28)
        }
        .background(palette.surface)
        .scrollFade()
        .quickLookPreview($preview)
        .onAppear {
            guard !primed else { return }
            primed = true
            chosen = Set(dups.map(\.id))
        }
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

    private func row(_ c: Candidate) -> some View {
        let on = chosen.contains(c.id)
        return HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? palette.primary : palette.outline)
            Thumbnail(file: c.file, side: 80)
                .frame(width: 44, height: 33)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onTapGesture { preview = c.file.url }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.file.name).font(.system(size: 13, weight: .bold)).lineLimit(1).truncationMode(.middle)
                Text("\(c.project.name) · \(Format.folder(c.file.path)) · \(c.keep)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            }
            Spacer()
            Text(Format.size(c.file.size)).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.onSurfaceVariant)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: on ? 20 : 12, style: .continuous).fill(on ? palette.secondaryContainer : .clear))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.fast) { if on { chosen.remove(c.id) } else { chosen.insert(c.id) } } }
        .contextMenu {
            Button("Show in Finder") { FileActions.reveal(c.file) }
            Button("Quick Look") { preview = c.file.url }
        }
    }
}
