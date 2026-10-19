import SwiftUI
import AppKit
import QuickLook
import StrataCore

/// Horizontal positions: one card per version, with extra room for long pauses between saves
/// so time *feels* right, without wasting the screen on empty months.
struct TimelineLayout {
    static let cardWidth: CGFloat = 188
    static let gutter: CGFloat = 26
    static let monthRow: CGFloat = 30
    static let dateRow: CGFloat = 48
    static let cardHeight: CGFloat = 206
    static let lineGap: CGFloat = 26
    static let dotRow: CGFloat = 30
    /// Y of the river line inside the timeline.
    static var lineY: CGFloat { monthRow + dateRow + 8 + cardHeight + lineGap + dotRow / 2 }

    let centers: [CGFloat]
    let dates: [Date]
    let width: CGFloat

    init(versions: [ProjectFile]) {
        dates = versions.map(\.file.modified)
        var xs: [CGFloat] = []
        var x: CGFloat = 40 + Self.cardWidth / 2
        for (i, d) in dates.enumerated() {
            if i > 0 {
                let days = max(0, d.timeIntervalSince(dates[i - 1])) / 86400
                x += Self.cardWidth + Self.gutter + CGFloat(min(180, 36 * log2(1 + days)))
            }
            xs.append(x)
        }
        centers = xs
        width = (xs.last ?? 0) + Self.cardWidth / 2 + 56
    }

    var drawDuration: Double { min(2.2, 0.6 + 0.14 * Double(centers.count)) }

    /// When the line reaches version `i` while drawing.
    func delay(_ i: Int) -> Double {
        guard let first = centers.first, let last = centers.last, last > first else { return 0.1 }
        return drawDuration * Double((centers[i] - first) / (last - first))
    }

    /// Indices where a new month starts (always includes the first version).
    var monthStarts: [Int] {
        let cal = Calendar.current
        return dates.indices.filter { i in
            i == 0 || !cal.isDate(dates[i], equalTo: dates[i - 1], toGranularity: .month)
        }
    }
}

// MARK: - Timeline

struct RiverTimeline: View {
    @Environment(\.palette) private var palette
    let project: ProjectGroup
    let layout: TimelineLayout
    let selectedID: String
    let revealed: Bool
    let select: (ProjectFile) -> Void
    let open: (ProjectFile) -> Void

    var body: some View {
        let versions = project.versions
        let points = layout.centers.map { CGPoint(x: $0, y: TimelineLayout.lineY) }
        ZStack(alignment: .topLeading) {
            // The river: a soft wave from the first version to the latest, drawn on appear.
            River(points: points)
                .stroke(palette.outlineVariant, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .opacity(0.5)
            River(points: points)
                .trim(from: 0, to: revealed ? 1 : 0)
                .stroke(LinearGradient(colors: [palette.outline, palette.primary],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .animation(.easeInOut(duration: layout.drawDuration), value: revealed)

            monthMarkers

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(versions.enumerated()), id: \.element.id) { i, version in
                    Color.clear.frame(width: leadingSpace(i), height: 1)
                    VersionColumn(version: version,
                                  exports: project.exports(of: version),
                                  isFirst: i == 0,
                                  isLast: i == versions.count - 1,
                                  selectedID: selectedID,
                                  select: select, open: open)
                        .frame(width: TimelineLayout.cardWidth)
                        .opacity(revealed ? 1 : 0)
                        .scaleEffect(revealed ? 1 : 0.7, anchor: .bottom)
                        .offset(y: revealed ? 0 : 40)
                        .animation(Motion.standard.delay(layout.delay(i)), value: revealed)
                        .id(version.id)
                }
            }
            .padding(.top, TimelineLayout.monthRow)
        }
        .frame(width: layout.width, alignment: .topLeading)
    }

    private func leadingSpace(_ i: Int) -> CGFloat {
        let half = TimelineLayout.cardWidth / 2
        return i == 0 ? layout.centers[0] - half : layout.centers[i] - layout.centers[i - 1] - TimelineLayout.cardWidth
    }

    /// "OCTOBER 2026" chapter labels with a dashed divider in the gap where the month changes.
    private var monthMarkers: some View {
        ForEach(layout.monthStarts, id: \.self) { i in
            let half = TimelineLayout.cardWidth / 2
            let x = i == 0 ? layout.centers[0] - half : (layout.centers[i - 1] + layout.centers[i]) / 2
            ZStack(alignment: .topLeading) {
                if i > 0 {
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 18))
                        p.addLine(to: CGPoint(x: x, y: TimelineLayout.lineY + 40))
                    }
                    .stroke(palette.outlineVariant, style: StrokeStyle(lineWidth: 1.2, dash: [3, 5]))
                }
                Text(Format.monthYear.string(from: layout.dates[i]).uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(palette.tertiary)
                    .fixedSize()
                    .offset(x: i == 0 ? x + 4 : x + 10, y: 0)
            }
            .opacity(revealed ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(layout.delay(i)), value: revealed)
        }
    }
}

/// A gentle wave through every version's position.
struct River: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for i in 1..<max(points.count, 1) where i < points.count {
            let a = points[i - 1], b = points[i]
            let dx = b.x - a.x
            let amp: CGFloat = (i % 2 == 0 ? 1 : -1) * min(14, dx / 18)
            p.addCurve(to: b, control1: CGPoint(x: a.x + dx * 0.35, y: a.y + amp),
                       control2: CGPoint(x: b.x - dx * 0.35, y: b.y - amp))
        }
        return p
    }
}

struct VersionColumn: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    @Environment(\.versionActions) private var actions
    let version: ProjectFile
    let exports: [ProjectFile]
    let isFirst: Bool
    let isLast: Bool
    let selectedID: String
    let select: (ProjectFile) -> Void
    let open: (ProjectFile) -> Void

    @ViewState private var hovering = false
    private var isSelected: Bool { selectedID == version.id }

    var body: some View {
        VStack(spacing: 0) {
            dateTile.frame(height: TimelineLayout.dateRow)
            Spacer().frame(height: 8)
            card.frame(height: TimelineLayout.cardHeight)
            Spacer().frame(height: TimelineLayout.lineGap)
            NodeDot(kind: dotKind, selected: isSelected).frame(height: TimelineLayout.dotRow)
            badges.padding(.top, 8)
            if !exports.isEmpty { exportList.padding(.top, 2) }
        }
    }

    private var dotKind: NodeDot.Kind {
        if isLast { return .latest }
        if isFirst { return .origin }
        if version.isRecovered { return .recovered }
        return .regular
    }

    private var dateTile: some View {
        let d = version.file.modified
        return HStack(spacing: 10) {
            VStack(spacing: -2) {
                Text(Format.dayNumber.string(from: d)).font(.system(size: 19, weight: .heavy))
                Text(Format.monthShort.string(from: d).uppercased()).font(.system(size: 9.5, weight: .heavy))
            }
            .frame(width: 46, height: 46)
            .background(RoundedRectangle(cornerRadius: isSelected ? 23 : 14, style: .continuous)
                .fill(isSelected ? palette.primary : palette.surfaceContainerHigh))
            .foregroundStyle(isSelected ? palette.onPrimary : palette.onSurface)
            VStack(alignment: .leading, spacing: 1) {
                Text(weekday(d)).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.onSurface)
                Text(Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
                     ? Format.time.string(from: d) : "\(Calendar.current.component(.year, from: d)) · \(Format.time.string(from: d))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .animation(Motion.standard, value: isSelected)
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return f.string(from: d)
    }

    private var radius: CGFloat { hovering || isSelected ? 28 : 22 }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                .overlay(Thumbnail(file: version.file))
                .overlay(alignment: .topTrailing) { KindPill(ext: version.file.fileExtension).padding(7) }
                .clipShape(MorphRect(radius: radius - 10))
            Text(version.file.name)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(isSelected ? palette.onPrimaryContainer : palette.onSurface)
                .lineLimit(1).truncationMode(.middle)
            Label(Format.shortFolder(version.file.path), systemImage: "folder.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? palette.onPrimaryContainer.opacity(0.75) : palette.onSurfaceVariant)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var cardSurface: some View {
        let fill: Color = isSelected ? palette.primaryContainer : palette.surfaceContainerLow
        return cardContent
            .background(MorphRect(radius: radius).fill(fill))
    }

    private var card: some View {
        return cardSurface
            .offset(y: hovering ? -6 : 0)
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Rectangle())
            .onHover { h in withAnimation(Motion.fast) { hovering = h } }
            .onTapGesture(count: 2) { open(version) }
            .onTapGesture { select(version) }
            .materialContextMenu { VersionMenu(file: version) }
            .help(version.file.path)
            .animation(Motion.standard, value: isSelected)
    }

    private var badges: some View {
        HStack(spacing: 5) {
            if isFirst { Pill(text: "First", fg: palette.surface, bg: palette.onSurface) }
            if isLast { Pill(text: "Latest", fg: palette.onPrimary, bg: palette.primary, icon: "sparkle") }
            if version.isRecovered { Pill(text: "Recovered", fg: palette.onWarningContainer, bg: palette.warningContainer, icon: "bolt.fill") }
            if version.isDuplicate { Pill(text: "Duplicate", fg: palette.onSurfaceVariant, bg: palette.surfaceContainerHighest, icon: "plus.square.on.square") }
            if let status = version.file.status { Pill(text: status.rawValue, fg: palette.onTertiaryContainer, bg: palette.tertiaryContainer, icon: status.symbol) }
            if !library.note(for: version.file).isEmpty {
                Pill(text: "", fg: palette.onSecondaryContainer, bg: palette.secondaryContainer, icon: "text.bubble.fill")
                    .help(library.note(for: version.file))
            }
        }
        .frame(minHeight: 24)
    }

    private var exportList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(palette.outline).frame(width: 1.5, height: 12)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(exports.prefix(4)) { export in
                    HStack(spacing: 8) {
                        Thumbnail(file: export.file, side: 64)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(export.file.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(5)
                    .background(Capsule().fill(selectedID == export.id ? palette.primaryContainer : palette.surfaceContainer))
                    .contentShape(Capsule())
                    .onTapGesture(count: 2) { open(export) }
                    .onTapGesture { select(export) }
                    .help("\(export.file.name) · \(Format.full.string(from: export.file.modified))")
                    .materialContextMenu { VersionMenu(file: export) }
                }
                if exports.count > 4 {
                    Text("+\(exports.count - 4) more exports")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant).padding(.leading, 8)
                }
            }
        }
    }
}

/// The marker on the river. Latest rotates; the selection morphs into a cookie.
struct NodeDot: View {
    enum Kind { case origin, latest, recovered, regular }
    @Environment(\.palette) private var palette
    let kind: Kind
    let selected: Bool
    @ViewState private var spin = false

    var body: some View {
        ZStack {
            switch kind {
            case .latest:
                Cookie(lobes: 9, depth: 0.2)
                    .fill(palette.primary)
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Image(systemName: "sparkle").font(.system(size: 10, weight: .black)).foregroundStyle(palette.onPrimary)
            case .origin:
                Cookie(lobes: 6, depth: selected ? 0.22 : 0)
                    .fill(palette.onSurface)
                    .frame(width: selected ? 24 : 16, height: selected ? 24 : 16)
            case .recovered:
                Cookie(lobes: 6, depth: selected ? 0.22 : 0)
                    .fill(palette.warning)
                    .frame(width: selected ? 26 : 20, height: selected ? 26 : 20)
                    .overlay(Image(systemName: "bolt.fill").font(.system(size: 9, weight: .black)).foregroundStyle(palette.surface))
            case .regular:
                Cookie(lobes: 7, depth: selected ? 0.22 : 0)
                    .fill(selected ? palette.primary : palette.surface)
                    .overlay(Cookie(lobes: 7, depth: selected ? 0.22 : 0).stroke(palette.primary, lineWidth: 3))
                    .frame(width: selected ? 24 : 15, height: selected ? 24 : 15)
            }
        }
        .animation(Motion.standard, value: selected)
        .onAppear {
            guard kind == .latest, !Motion.reduced else { return }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

// MARK: - Overview bar (true-to-scale time)

/// The whole project on one bar, positioned by real date: every version and export at a glance.
struct Overview: View {
    @Environment(\.palette) private var palette
    let project: ProjectGroup
    let selectedID: String
    let select: (ProjectFile) -> Void

    var body: some View {
        let start = project.files.map(\.file.modified).min() ?? Date()
        let end = project.files.map(\.file.modified).max() ?? Date()
        VStack(spacing: 6) {
            GeometryReader { geo in
                let inset: CGFloat = 22
                let w = geo.size.width - inset * 2
                let span = max(end.timeIntervalSince(start), 1)
                let x: (Date) -> CGFloat = { d in
                    end == start ? geo.size.width / 2 : inset + w * CGFloat(d.timeIntervalSince(start) / span)
                }
                let selectedFile = project.files.first { $0.id == selectedID } ?? project.latest
                ZStack(alignment: .topLeading) {
                    Capsule().fill(palette.surfaceContainer)
                    Capsule().fill(palette.primary.opacity(0.16))
                        .frame(width: max(44, x(selectedFile.file.modified) + 22))
                        .animation(Motion.standard, value: selectedID)
                    ForEach(ticks(start, end), id: \.self) { t in
                        Rectangle().fill(palette.outlineVariant)
                            .frame(width: 1, height: 12)
                            .position(x: x(t), y: 32)
                    }
                    ForEach(project.files.filter(\.isExport)) { f in
                        Circle().strokeBorder(palette.outline, lineWidth: 1.5)
                            .frame(width: 7, height: 7)
                            .position(x: x(f.file.modified), y: 13)
                            .onTapGesture { select(f) }
                            .help("Export · \(f.file.name) · \(Format.date(f.file.modified))")
                    }
                    ForEach(project.versions) { v in
                        let isSel = v.id == selectedID
                        let isLatest = v.id == project.latest.id
                        Cookie(lobes: 8, depth: isSel ? 0.22 : 0)
                            .fill(isSel || isLatest ? palette.primary : (v.isRecovered ? palette.warning : palette.onSurfaceVariant))
                            .frame(width: isSel ? 20 : 10, height: isSel ? 20 : 10)
                            .position(x: x(v.file.modified), y: 22)
                            .onTapGesture { select(v) }
                            .help("\(v.file.name) · \(Format.full.string(from: v.file.modified))")
                            .animation(Motion.standard, value: isSel)
                    }
                }
            }
            .frame(height: 44)
            HStack {
                Text(Format.date(start))
                Spacer()
                Text("\(project.files.count) files over \(duration(start, end))")
                Spacer()
                Text(Format.date(end))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.onSurfaceVariant)
            .padding(.horizontal, 10)
        }
    }

    /// Month starts between two dates (years if the span is long).
    private func ticks(_ a: Date, _ b: Date) -> [Date] {
        let cal = Calendar.current
        let months = cal.dateComponents([.month], from: a, to: b).month ?? 0
        let unit: Calendar.Component = months > 30 ? .year : .month
        guard var t = cal.dateInterval(of: unit, for: a)?.end else { return [] }
        var out: [Date] = []
        while t < b && out.count < 60 {
            out.append(t)
            t = cal.date(byAdding: unit, value: 1, to: t) ?? b
        }
        return out
    }

    private func duration(_ a: Date, _ b: Date) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour]
        f.maximumUnitCount = 1
        f.unitsStyle = .full
        return b.timeIntervalSince(a) < 3600 ? "less than an hour" : (f.string(from: a, to: b) ?? "")
    }
}

// MARK: - Inspector

/// Draft → In Review → Sent → Approved → Final, as a connected M3 button group. Click the active one to clear it.
struct StatusGroup: View {
    @Environment(\.palette) private var palette
    let status: VersionStatus?
    let set: (VersionStatus?) -> Void
    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(VersionStatus.allCases, id: \.self) { s in
                let on = s == status
                Button { set(on ? nil : s) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: on ? "checkmark" : s.symbol).font(.system(size: 10, weight: .bold))
                        Text(s.rawValue).font(.system(size: 12, weight: on ? .bold : .semibold)).lineLimit(1).fixedSize()
                    }
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(Capsule().fill(on ? palette.tertiary : palette.surfaceContainerHighest))
                    .foregroundStyle(on ? palette.surface : palette.onSurfaceVariant)
                }
                .buttonStyle(PressScale())
                .help(on ? "\(s.rawValue) · click to clear" : "Mark as \(s.rawValue) (saved as a Finder tag)")
            }
        }
        .animation(Motion.fast, value: status)
    }
}

/// Right-click menu for any version or export.
struct VersionMenu: View {
    @EnvironmentObject var library: Library
    @Environment(\.versionActions) private var actions
    let file: ProjectFile

    var body: some View {
        Button("Open") { FileActions.open(file.file) }
        Button("Show in Finder") { FileActions.reveal(file.file) }
        if !file.isExport { Button("Compare with the version before") { actions.compare(file) } }
        MaterialMenu("Status") {
            ForEach(VersionStatus.allCases, id: \.self) { s in
                Button { library.setStatus(s, for: file.file) } label: {
                    if file.file.status == s { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) }
                }
            }
            Divider()
            Button("None") { library.setStatus(nil, for: file.file) }
        }
        Divider()
        Button("Move to another project…") { actions.move(file) }
        Button("Remove from this project") { library.detach(file.file) }
    }
}

/// Shows "icon + title", or just the icon (with the title as tooltip) when space is tight.
struct AdaptiveLabel: LabelStyle {
    var iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 7) { configuration.icon; configuration.title.lineLimit(1) }.fixedSize()
        }
    }
}
