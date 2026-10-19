import SwiftUI
import AppKit
import QuickLook
import UniformTypeIdentifiers
import StrataCore

// MARK: - Delivery pack

enum Delivery {
    /// Zips the latest version of each project plus its exports into one file you choose.
    @MainActor
    static func prepare(name: String, projects: [ProjectGroup], library: Library) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "\(name) – delivery \(day.string(from: Date())).zip"
        panel.message = "The latest version of each project, with its PDF / PNG exports."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        var plan: [(folder: String, files: [CreativeFile])] = []
        for p in projects {
            let latest = p.latest
            plan.append((projects.count > 1 ? safe(p.name) : "", [latest.file] + p.exports(of: latest).map(\.file)))
        }
        library.show("Preparing \(destination.lastPathComponent)…")
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let staging = fm.temporaryDirectory.appendingPathComponent("strata-\(UUID().uuidString)")
            let root = staging.appendingPathComponent(safe(name))
            var copied = 0
            do {
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                for item in plan {
                    let dir = item.folder.isEmpty ? root : root.appendingPathComponent(item.folder)
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    for f in item.files {
                        let target = dir.appendingPathComponent(f.name)
                        if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: f.url, to: target); copied += 1 }
                    }
                }
                try? fm.removeItem(at: destination)
                let zip = Process()
                zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                zip.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, destination.path]
                try zip.run()
                zip.waitUntilExit()
                try? fm.removeItem(at: staging)
                let ok = zip.terminationStatus == 0
                let count = copied
                await MainActor.run {
                    if ok {
                        library.show("Delivery ready · \(count) files in \(destination.lastPathComponent)")
                        NSWorkspace.shared.activateFileViewerSelecting([destination])
                    } else {
                        library.show("Couldn't create the zip")
                    }
                }
            } catch {
                try? fm.removeItem(at: staging)
                let message = error.localizedDescription
                await MainActor.run { library.show("Delivery failed: \(message)") }
            }
        }
    }

    /// A folder name that can't escape the delivery folder or confuse Finder ("..", "/", control characters).
    nonisolated static func safe(_ s: String) -> String {
        let cleaned = s.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) || "/:\\".unicodeScalars.contains($0) ? "-" : Character($0) }
        var name = String(cleaned).trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(100)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled" : name
    }
}

// MARK: - Brand kit

/// Everything that defines a client visually, gathered from their files: logos, colours, fonts.
struct BrandKitView: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    let collection: Client
    @ViewState private var colors: [OKLCH] = []
    @ViewState private var loadingColors = true
    @ViewState private var preview: URL?

    private let logoColumns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12, alignment: .top)]

    /// Newest file per logo name: "norvia logo white.png", "Norvia Logo.ai"…
    private var logos: [CreativeFile] {
        var seen = Set<String>()
        return collection.recentFiles.filter { f in
            guard f.name.lowercased().contains("logo") else { return false }
            let key = NameNormalizer.key(for: f.name) ?? f.baseName.lowercased()
            return seen.insert(key + f.fileExtension).inserted
        }
        .prefix(18).map { $0 }
    }

    private var fonts: [(family: String, count: Int)] {
        var count: [String: Int] = [:]
        for f in collection.allFiles {
            for font in f.xmp?.fonts ?? [] {
                // PDFs prefix embedded fonts with a random subset tag: "AVAAAA+Poppins Bold".
                let clean = font.replacingOccurrences(of: "^[A-Z]{6}\\+", with: "", options: .regularExpression)
                count[clean, default: 0] += 1
            }
        }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Colours", "Pulled from this client's latest artwork · click to copy") {
                if loadingColors {
                    HStack(spacing: 12) { MorphingLoader(size: 28); Text("Reading colours…").foregroundStyle(palette.onSurfaceVariant) }
                } else if colors.isEmpty {
                    Text("No artwork with colour yet.").foregroundStyle(palette.onSurfaceVariant)
                } else {
                    HStack(spacing: 12) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                            Swatch(color: c, big: i == 0) { library.copy(c.hex) }
                        }
                    }
                }
            }
            group("Fonts", fonts.isEmpty ? "No font information found in this client's Illustrator / PDF files" : "Used in this client's documents") {
                ForEach(fonts.prefix(8), id: \.family) { font in
                    FontRow(family: font.family, uses: font.count) { library.copy(font.family, label: "font name") }
                }
            }
            group("Logos", logos.isEmpty ? "No file with “logo” in its name" : "\(logos.count) logo files · click to preview, double-click to open") {
                LazyVGrid(columns: logoColumns, alignment: .leading, spacing: 12) {
                    ForEach(logos) { f in
                        FileTile(file: f) { preview = f.url }
                            .draggable(f.url)
                    }
                }
            }
        }
        .quickLookPreview($preview)
        .task(id: collection.id) { await loadColors() }
    }

    private func group<C: View>(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.display(20)).foregroundStyle(palette.onSurface)
                Text(subtitle).font(.system(size: 12.5, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.surfaceContainerLow))
    }

    /// Weighted colours across the newest artwork, merged when they look alike.
    private func loadColors() async {
        loadingColors = true
        let candidates = collection.recentFiles.filter { $0.kind != .video }.prefix(24)
        var found: [(OKLCH, Double)] = []
        for f in candidates {
            guard let image = await ThumbnailStore.shared.image(for: f.url, side: 128, modified: f.modified) else { continue }
            found += ColorExtractor.palette(from: image, count: 5)
        }
        var merged: [(OKLCH, Double)] = []
        for (c, w) in found.sorted(by: { $0.1 > $1.1 }) {
            if let i = merged.firstIndex(where: { distance($0.0, c) < 0.07 }) { merged[i].1 += w } else { merged.append((c, w)) }
        }
        withAnimation(Motion.standard) {
            colors = merged.sorted { $0.1 > $1.1 }.prefix(10).map(\.0)
            loadingColors = false
        }
    }

    private func distance(_ a: OKLCH, _ b: OKLCH) -> Double {
        let ax = a.c * cos(a.h * .pi / 180), ay = a.c * sin(a.h * .pi / 180)
        let bx = b.c * cos(b.h * .pi / 180), by = b.c * sin(b.h * .pi / 180)
        return sqrt(pow(a.l - b.l, 2) + pow(ax - bx, 2) + pow(ay - by, 2))
    }
}

private struct Swatch: View {
    @Environment(\.palette) private var palette
    let color: OKLCH
    let big: Bool
    let copy: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: copy) {
            VStack(spacing: 8) {
                MorphShape(from: .softSquare, to: .cookie9, progress: hovering ? 1 : 0)
                    .fill(color.color)
                    .frame(width: big ? 74 : 58, height: big ? 74 : 58)
                    .shadow(color: color.color.opacity(0.4), radius: hovering ? 12 : 4, y: 4)
                Text(color.hex).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.onSurface)
            }
        }
        .buttonStyle(PressScale())
        .onHover { h in withAnimation(Motion.fast) { hovering = h } }
        .help("Copy \(color.hex)")
    }
}

private struct FontRow: View {
    @Environment(\.palette) private var palette
    let family: String
    let uses: Int
    let copy: () -> Void

    private var installed: Bool { NSFontManager.shared.availableMembers(ofFontFamily: family) != nil }

    var body: some View {
        HStack(spacing: 14) {
            Text("Aa")
                .font(installed ? .custom(family, size: 28) : .system(size: 28, weight: .bold, design: .serif))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.secondaryContainer))
                .foregroundStyle(palette.onSecondaryContainer)
            VStack(alignment: .leading, spacing: 2) {
                Text(family).font(installed ? .custom(family, size: 17) : .system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                Text("\(uses) file\(uses == 1 ? "" : "s")\(installed ? "" : " · not installed on this Mac")")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(installed ? palette.onSurfaceVariant : palette.warning)
            }
            Spacer()
            Button("Copy name", action: copy).buttonStyle(.link)
        }
    }
}

// MARK: - Activity

/// When you worked for this client: a day-by-day heatmap built from save dates.
struct ActivityView: View {
    @Environment(\.palette) private var palette
    let collection: Client
    private let weeks = 26

    private var savesPerDay: [Date: Int] {
        let cal = Calendar.current
        var out: [Date: Int] = [:]
        for f in collection.allFiles { out[cal.startOfDay(for: f.modified), default: 0] += 1 }
        return out
    }

    var body: some View {
        let perDay = savesPerDay
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today)!
        let gridStart = cal.date(byAdding: .day, value: -(cal.component(.weekday, from: start) - 1), to: start)!
        let maxCount = max(perDay.values.max() ?? 1, 1)
        let last30 = perDay.filter { $0.key > cal.date(byAdding: .day, value: -30, to: today)! }
        let projects30 = collection.projects
            .map { p in (p, p.files.filter { $0.file.modified > cal.date(byAdding: .day, value: -30, to: today)! }.count) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                stat("\(last30.count)", "days worked in the last 30")
                stat("\(last30.values.reduce(0, +))", "saves in the last 30 days")
                stat(Format.date(collection.lastModified), "last save")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 6 months").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.onSurface)
                HStack(alignment: .top, spacing: 4) {
                    ForEach(0..<(weeks + 1), id: \.self) { w in
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { d in
                                let day = cal.date(byAdding: .day, value: w * 7 + d, to: gridStart)!
                                let n = perDay[day] ?? 0
                                RoundedRectangle(cornerRadius: n > 0 ? 7 : 4, style: .continuous)
                                    .fill(day > today ? .clear : (n == 0 ? palette.surfaceContainerHighest : palette.primary.opacity(0.3 + 0.7 * Double(n) / Double(maxCount))))
                                    .frame(width: 15, height: 15)
                                    .help("\(Format.dayYear.string(from: day)) · \(n) save\(n == 1 ? "" : "s")")
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.surfaceContainerLow))

            if !projects30.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Busiest projects this month").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.onSurface)
                    let top = projects30.first?.1 ?? 1
                    ForEach(projects30.prefix(6), id: \.0.id) { p, n in
                        HStack(spacing: 10) {
                            Text(p.name).font(.system(size: 13, weight: .semibold)).frame(width: 220, alignment: .leading).lineLimit(1)
                            Capsule().fill(palette.primary)
                                .frame(width: max(14, 300 * CGFloat(n) / CGFloat(top)), height: 14)
                            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.onSurfaceVariant)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.surfaceContainerLow))
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.display(30)).foregroundStyle(palette.onTertiaryContainer)
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.onTertiaryContainer.opacity(0.8))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MorphRect(radius: 26).fill(palette.tertiaryContainer))
    }
}
