import SwiftUI
import AppKit
import StrataCore

@main
struct StrataApp: App {
    @StateObject private var library = Library()
    @StateObject private var quickFind = QuickFindState.shared
    @AppStorage(Prefs.accentKey) private var accent = 0

    init() {
        Prefs.register()
        // Launched as a bare executable (swift run) the app would otherwise stay in the background.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Strata", id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(quickFind)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan Folders") { library.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Find Anything…") { withAnimation(Motion.standard) { quickFind.isOpen = true } }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo Last Strata Change") { library.undo() }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                    .disabled(!library.canUndo)
            }
        }

        Settings {
            SettingsView().environmentObject(library)
        }

        MenuBarExtra {
            MenuBarPanel()
                .materialMenuHost()
                .environmentObject(library)
                .environmentObject(quickFind)
                .themed(Prefs.accent(accent))
        } label: {
            // The menu bar item exists from launch even when no window is open,
            // so app-wide setup (global shortcut, update check) happens here.
            MenuBarLabel(setup: launchSetup)
        }
        .menuBarExtraStyle(.window)
    }

    private func launchSetup() {
        Prefs.applyAppearance(UserDefaults.standard.string(forKey: Prefs.appearanceKey) ?? "System")
        if Prefs.crashAlerts { Library.requestNotificationPermission() }
        SpotlightSearch.shared.library = library
        HotKey.shared.onPress = { SpotlightSearch.shared.toggle() }
        HotKey.shared.setEnabled(UserDefaults.standard.bool(forKey: Prefs.hotkeyKey))
        Updater.shared.checkIfDue { message in library.show(message) }
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

/// The menu bar icon. It is always alive, so it's where Strata learns how to reopen its main window.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let setup: () -> Void
    private static var didSetup = false

    var body: some View {
        Image(nsImage: MenuBarIcon.image)
            .onAppear {
                WindowOpener.open = { openWindow(id: "main") }
                guard !Self.didSetup else { return }
                Self.didSetup = true
                setup()
            }
    }
}
