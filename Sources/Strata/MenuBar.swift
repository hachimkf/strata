import SwiftUI
import AppKit
import StrataCore

/// The menu bar glyph: Strata's folder with the "open latest" arrow, as a template image
/// so macOS tints it for light / dark menu bars like every other status item.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 20, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            // Two sheets fanning out of the folder, like the app icon.
            func sheet(_ rect: NSRect, angle: CGFloat) -> NSBezierPath {
                let path = NSBezierPath(roundedRect: rect, xRadius: 1.4, yRadius: 1.4)
                let t = NSAffineTransform()
                t.translateX(by: rect.midX, yBy: rect.midY)
                t.rotate(byDegrees: angle)
                t.translateX(by: -rect.midX, yBy: -rect.midY)
                path.transform(using: t as AffineTransform)
                return path
            }
            sheet(NSRect(x: 3, y: 5.5, width: 7, height: 9.5), angle: 14).fill()
            let front = sheet(NSRect(x: 10, y: 5.5, width: 7, height: 9.5), angle: -12)
            NSGraphicsContext.current?.compositingOperation = .clear
            front.lineWidth = 1.8
            front.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            front.fill()
            // Folder body, with a thin gap cut around it so it reads in front of the sheets.
            let folder = NSBezierPath()
            folder.move(to: NSPoint(x: 1, y: 2.5))
            folder.line(to: NSPoint(x: 1, y: 8.5))
            folder.curve(to: NSPoint(x: 2.5, y: 10), controlPoint1: NSPoint(x: 1, y: 9.5), controlPoint2: NSPoint(x: 1.5, y: 10))
            folder.line(to: NSPoint(x: 6.5, y: 10))
            folder.line(to: NSPoint(x: 8, y: 8.5))
            folder.line(to: NSPoint(x: 17.5, y: 8.5))
            folder.curve(to: NSPoint(x: 19, y: 7), controlPoint1: NSPoint(x: 18.5, y: 8.5), controlPoint2: NSPoint(x: 19, y: 8))
            folder.line(to: NSPoint(x: 19, y: 2.5))
            folder.curve(to: NSPoint(x: 17.5, y: 1), controlPoint1: NSPoint(x: 19, y: 1.5), controlPoint2: NSPoint(x: 18.5, y: 1))
            folder.line(to: NSPoint(x: 2.5, y: 1))
            folder.curve(to: NSPoint(x: 1, y: 2.5), controlPoint1: NSPoint(x: 1.5, y: 1), controlPoint2: NSPoint(x: 1, y: 1.5))
            folder.close()
            NSGraphicsContext.current?.compositingOperation = .clear
            folder.lineWidth = 2.4
            folder.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            folder.fill()
            // Arrow badge, punched out of the folder.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 11.6, y: 1.9, width: 6, height: 6)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let arrow = NSBezierPath()
            arrow.lineWidth = 1.2
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 13.4, y: 3.7)); arrow.line(to: NSPoint(x: 15.9, y: 6.2))
            arrow.move(to: NSPoint(x: 13.9, y: 6.2)); arrow.line(to: NSPoint(x: 15.9, y: 6.2)); arrow.line(to: NSPoint(x: 15.9, y: 4.2))
            arrow.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }()
}

/// The menu bar panel: find anything, reopen what you just saved, rescan.
struct MenuBarPanel: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    @Environment(\.openWindow) private var openWindow
    @ViewState private var query = ""
    @FocusState private var searching: Bool

    private struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let file: CreativeFile
        let name: String
    }

    private var results: [Row] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        func hit(_ s: String) -> Bool { words.allSatisfy { s.lowercased().contains($0) } }
        var rows: [Row] = []
        for c in library.collections where hit(c.name) {
            if let latest = c.latest {
                rows.append(Row(id: c.id, title: c.name, subtitle: "Client · newest: \(latest.name)", file: latest, name: c.name))
            }
        }
        for p in library.projects where hit(p.name + " " + (library.collection(containing: p.id)?.name ?? "")) {
            rows.append(Row(id: p.id, title: p.name, subtitle: "Latest · \(Format.date(p.latest.file.modified)) · \(p.latest.file.name)",
                            file: p.latest.file, name: p.name))
        }
        return Array(rows.prefix(7))
    }

    private var recentProjects: [Row] {
        library.projects.prefix(5).map {
            Row(id: $0.id, title: $0.name, subtitle: "Latest · \(Format.date($0.latest.file.modified)) · \($0.latest.file.name)",
                file: $0.latest.file, name: $0.name)
        }
    }

    /// The last few files saved anywhere you watch: one click back into what you were doing.
    private var justSaved: [CreativeFile] {
        (library.projects.flatMap { $0.files.map(\.file) } + library.loose)
            .sorted { $0.modified > $1.modified }
            .prefix(4).map { $0 }
    }

    private var recentRecoveries: [(ProjectGroup, ProjectFile)] {
        let week = Date().addingTimeInterval(-7 * 86400)
        return library.projects.flatMap { p in p.files.filter { $0.isRecovered && $0.file.modified > week }.map { (p, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            searchField
            if !query.isEmpty {
                section(results.isEmpty ? "No match for “\(query)”" : "Open latest version")
                ForEach(results) { row($0) }
            } else {
                if !recentRecoveries.isEmpty {
                    section("Recovered after a crash · this week")
                    ForEach(recentRecoveries.prefix(2), id: \.1.id) { project, file in
                        fileRow(file.file, subtitle: "\(project.name) · \(Format.ago(file.file.modified))", warning: true)
                    }
                }
                section("Recent projects")
                ForEach(recentProjects) { row($0) }
                section("Just saved")
                ForEach(justSaved, id: \.path) { fileRow($0, subtitle: "\(Format.ago($0.modified)) · \(Format.shortFolder($0.path))", warning: false) }
            }
            footer
        }
        .padding(12)
        .frame(width: 360)
        .background(palette.surfaceContainerLow)
        .onAppear { searching = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Strata").font(.display(17)).foregroundStyle(palette.onSurface)
                Text(library.isScanning ? "Reading folders…" : "\(library.fileCount.formatted()) files · updated \(library.lastScan.map { Format.ago($0) } ?? "—")")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer()
            Button { library.rescan() } label: {
                Group {
                    if library.isScanning { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .background(palette.secondaryContainer, in: Circle())
                .foregroundStyle(palette.onSecondaryContainer)
            }
            .buttonStyle(PressScale())
            .help("Rescan watched folders")
            .disabled(library.isScanning)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .bold))
            TextField("Open the latest of…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium))
                .focused($searching)
                .onSubmit { if let first = results.first { FileActions.open(first.file) } }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(palette.onSurfaceVariant)
        .padding(.horizontal, 12).frame(height: 36)
        .background(Capsule().fill(palette.surfaceContainerHighest))
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.onSurfaceVariant)
            .padding(.leading, 6).padding(.top, 4)
    }

    private func row(_ r: Row) -> some View {
        Button { FileActions.open(r.file) } label: {
            HStack(spacing: 10) {
                ShapeAvatar(file: r.file, name: r.name, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(r.subtitle).font(.system(size: 10.5)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.primary)
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
        .help("Open \(r.file.name)")
        .contextMenu { Button("Show in Finder") { FileActions.reveal(r.file) } }
    }

    private func fileRow(_ f: CreativeFile, subtitle: String, warning: Bool) -> some View {
        Button { FileActions.open(f) } label: {
            HStack(spacing: 10) {
                Thumbnail(file: f, side: 72)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if warning {
                            Image(systemName: "bolt.fill").font(.system(size: 8, weight: .black))
                                .padding(3).background(palette.warning, in: Circle()).foregroundStyle(palette.surface)
                                .offset(x: 3, y: 3)
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
        .contextMenu { Button("Show in Finder") { FileActions.reveal(f) } }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            footerButton("macwindow", "Open Strata") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            footerButton("magnifyingglass", "Find… \(HotKey.shared.shortcut.display)") {
                SpotlightSearch.shared.show()
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape.fill").font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28).background(palette.surfaceContainerHigh, in: Circle())
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .buttonStyle(PressScale())
            .help("Settings")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28).background(palette.surfaceContainerHigh, in: Circle())
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .buttonStyle(PressScale())
            .help("Quit Strata")
        }
        .padding(.top, 6)
    }

    private func footerButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 30)
                .background(palette.secondaryContainer, in: Capsule())
                .foregroundStyle(palette.onSecondaryContainer)
        }
        .buttonStyle(PressScale())
    }
}
