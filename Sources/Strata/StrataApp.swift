import SwiftUI
import AppKit
import StrataCore

@main
struct StrataApp: App {
    @StateObject private var library = Library()

    init() {
        // Launched as a bare executable (swift run) the app would otherwise stay in the background.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Strata", id: "main") {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan Folders") { library.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra("Strata", systemImage: "square.stack.3d.up.fill") {
            MenuBarPanel().environmentObject(library)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Quick access from the menu bar: the latest version of your most recent projects, one click away.
struct MenuBarPanel: View {
    @EnvironmentObject var library: Library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent projects").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 4)
            ForEach(library.projects.prefix(6)) { project in
                Button { FileActions.open(project.latest.file) } label: {
                    HStack(spacing: 10) {
                        Thumbnail(file: project.latest.file, side: 80)
                            .frame(width: 40, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Text("Latest · \(Format.date(project.latest.file.modified)) · \(project.latest.file.name)")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MenuRowStyle())
                .help("Open \(project.latest.file.name)")
            }
            if library.projects.isEmpty {
                Text(library.isScanning ? "Scanning…" : "No projects yet").foregroundStyle(.secondary).padding(8)
            }
            Divider().padding(.vertical, 4)
            HStack {
                Button("Open Strata") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8).padding(.bottom, 4)
        }
        .padding(8)
        .frame(width: 340)
    }
}

struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0)))
            .modifier(HoverHighlight())
    }
}

struct HoverHighlight: ViewModifier {
    @ViewState private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
            .onHover { hovering = $0 }
    }
}
