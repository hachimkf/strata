import SwiftUI
import AppKit
import Carbon.HIToolbox
import StrataCore

/// A keyboard shortcut stored as a Carbon key code + Carbon modifier flags.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    // ⇧⌘B ("browse"): Space combinations clash with Siri ("Hold ⌘ Space"), keyboard switching (⌃⌥Space)
    // and Adobe zoom (⌘Space / ⌥⌘Space).
    static let defaultSearch = Shortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | shiftKey))

    static func load() -> Shortcut {
        let d = UserDefaults.standard
        guard d.object(forKey: "hotkeyCode") != nil else { return .defaultSearch }
        return Shortcut(keyCode: UInt32(d.integer(forKey: "hotkeyCode")), modifiers: UInt32(d.integer(forKey: "hotkeyMods")))
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "hotkeyMods")
    }

    /// From a key press in a recorder; nil unless at least one of ⌘ ⌥ ⌃ is held.
    init?(event: NSEvent) {
        let f = event.modifierFlags
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        guard m != 0 else { return nil }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: m)
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// "⌃⌥Space"
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Shortcut.keyName(Int(keyCode))
    }

    static func keyName(_ code: Int) -> String {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let n = named[code] { return n }
        let letters: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";",
        ]
        return letters[code] ?? "Key \(code)"
    }
}

/// System-wide shortcut (Carbon hot key: works while Strata runs in the background, no Accessibility permission).
@MainActor
final class HotKey: ObservableObject {
    static let shared = HotKey()
    var onPress: (() -> Void)?
    @Published private(set) var shortcut = Shortcut.load()
    /// False when another app already owns this combination.
    @Published private(set) var registered = false
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func setEnabled(_ on: Bool) { on ? register() : unregister() }

    func change(to new: Shortcut) {
        unregister()
        shortcut = new
        new.save()
        if UserDefaults.standard.bool(forKey: Prefs.hotkeyKey) { register() }
    }

    private func register() {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5354_5241), id: 1)   // "STRA"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        registered = status == noErr
        if !registered { ref = nil }
        UserDefaults.standard.set("\(shortcut.display) \(registered ? "registered" : "failed \(status)")", forKey: "hotkeyStatus")
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = false
    }
}

@MainActor
final class QuickFindState: ObservableObject {
    static let shared = QuickFindState()
    @Published var isOpen = false
    /// Where to go when the floating search asks the main window to show something.
    @Published var pending: SidebarItem?
}

/// Lets non-SwiftUI code (the floating panel, the hot key) open the main window.
@MainActor
enum WindowOpener {
    static var open: (() -> Void)?

    static func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Strata" && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            open?()
        }
    }
}

// MARK: - Spotlight-style floating search

/// A borderless panel that can take keyboard focus without bringing Strata's window forward.
final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SpotlightSearch {
    static let shared = SpotlightSearch()
    weak var library: Library?
    private var panel: SearchPanel?
    private var resignObserver: Any?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard let library else { return }
        let width: CGFloat = 680, height: CGFloat = 560
        if panel == nil {
            let p = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                                backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.isMovableByWindowBackground = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { _ in
                Task { @MainActor in SpotlightSearch.shared.hide() }
            }
            panel = p
        }
        guard let panel else { return }
        // Fresh view every time: empty query, first result selected.
        let accent = UserDefaults.standard.integer(forKey: Prefs.accentKey)
        let root = QuickFindView(floating: true,
                                 navigate: { item in
                                     SpotlightSearch.shared.hide()
                                     QuickFindState.shared.pending = item
                                     WindowOpener.showMain()
                                 },
                                 close: { SpotlightSearch.shared.hide() })
            .environmentObject(library)
            .themed(Prefs.accent(accent))
        panel.contentView = NSHostingView(rootView: root)
        // Upper third of the screen with the pointer, like Spotlight.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrame(NSRect(x: f.midX - width / 2, y: f.maxY - height - f.height * 0.12, width: width, height: height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }
}

/// Find anything. Inside Strata (⌘K): Return shows the client / project, ⌘Return opens its newest file.
/// As a floating panel from any app: Return opens the newest file, ⌘Return shows it in Strata.
struct QuickFindView: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    var floating = false
    let navigate: (SidebarItem) -> Void
    let close: () -> Void

    @ViewState private var query = ""
    @ViewState private var index = 0
    @ViewState private var monitor: Any?
    @FocusState private var focused: Bool

    struct Hit: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let kind: String
        let file: CreativeFile?
        let go: () -> Void
        let openLatest: (() -> Void)?
    }

    private var hits: [Hit] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let words = q.split(separator: " ").map(String.init)
        func matches(_ s: String) -> Bool { words.allSatisfy { s.lowercased().contains($0) } }
        var out: [Hit] = []
        let clients = q.isEmpty ? Array(library.collections.prefix(4)) : library.collections.filter { matches($0.name) }
        for c in clients.prefix(5) {
            out.append(Hit(id: c.id, title: c.name, subtitle: "Client · \(c.projects.count) projects · \(c.fileCount) files",
                           kind: "Client", file: c.latest,
                           go: { navigate(.collection(c.id)) },
                           openLatest: c.latest.map { f in { FileActions.open(f) } }))
        }
        let projects = q.isEmpty ? Array(library.projects.prefix(6)) : library.projects.filter { p in
            matches(p.name + " " + (library.collection(containing: p.id)?.name ?? ""))
        }
        for p in projects.prefix(8) {
            let client = library.collection(containing: p.id)?.name
            out.append(Hit(id: p.id, title: p.name,
                           subtitle: [client, "\(p.versions.count) versions", "latest \(Format.date(p.latest.file.modified))"].compactMap { $0 }.joined(separator: " · "),
                           kind: "Project", file: p.latest.file,
                           go: { navigate(.project(p.id)) },
                           openLatest: { FileActions.open(p.latest.file) }))
        }
        if !q.isEmpty {
            let files = (library.projects.flatMap { $0.files.map(\.file) } + library.loose).filter { matches($0.name) }
                .sorted { $0.modified > $1.modified }
            for f in files.prefix(8) {
                out.append(Hit(id: "file:" + f.path, title: f.name, subtitle: "\(Format.date(f.modified)) · \(Format.folder(f.path))",
                               kind: "File", file: f, go: { FileActions.open(f) }, openLatest: nil))
            }
        }
        return out
    }

    var body: some View {
        let results = hits
        ZStack(alignment: .top) {
            if !floating { Color.black.opacity(0.28).ignoresSafeArea().onTapGesture(perform: close) }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    MorphShape(from: .cookie9, to: .cookie9, progress: 0)
                        .fill(palette.primary).frame(width: 26, height: 26)
                        .overlay(Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .black)).foregroundStyle(palette.onPrimary))
                    TextField("Find a client, project or file…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .semibold))
                        .focused($focused)
                        .onSubmit { activate(results, latest: false) }
                    Text("esc").font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(palette.surfaceContainerHighest, in: Capsule())
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .padding(.horizontal, 20).frame(height: 64)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { i, hit in
                                row(hit, selected: i == index)
                                    .id(i)
                                    .onTapGesture { index = i; activate(results, latest: false) }
                            }
                            if results.isEmpty {
                                Text("Nothing matches “\(query)”").font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(palette.onSurfaceVariant).padding(30)
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: index) { withAnimation(Motion.fast) { proxy.scrollTo(index) } }
                }
                HStack(spacing: 14) {
                    hint("↑↓", "move")
                    hint("return", floating ? "open newest file" : "open")
                    hint("⌘ return", floating ? "show in Strata" : "open newest file")
                    Spacer()
                    if floating {
                        Text(HotKey.shared.shortcut.display).font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(palette.onSurfaceVariant.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(palette.surfaceContainer)
            }
            .frame(width: 640)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.surfaceContainerLow))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.outlineVariant.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(floating ? 0.35 : 0.3), radius: floating ? 30 : 40, y: floating ? 14 : 20)
            .padding(.top, floating ? 20 : 90)
            .padding(.horizontal, floating ? 20 : 0)
            .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
        }
        .onAppear {
            focused = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let count = hits.count
                switch event.keyCode {
                case 125: index = min(index + 1, max(count - 1, 0)); return nil          // ↓
                case 126: index = max(index - 1, 0); return nil                          // ↑
                case 53: close(); return nil                                             // esc
                case 36 where event.modifierFlags.contains(.command): activate(hits, latest: true); return nil
                default: return event
                }
            }
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .onChange(of: query) { index = 0 }
    }

    private func activate(_ results: [Hit], latest: Bool) {
        guard results.indices.contains(index) else { return }
        let hit = results[index]
        // Floating, the quick path (Return) is "open the newest file"; in the app it's "show it".
        let openFile = floating ? !latest : latest
        if openFile, let open = hit.openLatest { open() } else { hit.go() }
        close()
    }

    private func row(_ hit: Hit, selected: Bool) -> some View {
        HStack(spacing: 12) {
            ShapeAvatar(file: hit.file, name: hit.title, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    .foregroundStyle(selected ? palette.onSecondaryContainer : palette.onSurface)
                Text(hit.subtitle).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    .foregroundStyle(selected ? palette.onSecondaryContainer.opacity(0.8) : palette.onSurfaceVariant)
            }
            Spacer()
            Text(hit.kind).font(.system(size: 10.5, weight: .heavy))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(palette.surfaceContainerHighest, in: Capsule())
                .foregroundStyle(palette.onSurfaceVariant)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: selected ? 22 : 14, style: .continuous)
            .fill(selected ? palette.secondaryContainer : .clear))
        .contentShape(Rectangle())
        .animation(Motion.fast, value: selected)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 10.5, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(palette.surfaceContainerHighest, in: Capsule())
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(palette.onSurfaceVariant)
    }
}
