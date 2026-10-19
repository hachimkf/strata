import SwiftUI
import AppKit
import ServiceManagement
import StrataCore

struct SettingsView: View {
    @AppStorage(Prefs.accentKey) private var accent = 0

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            ClientSettings().tabItem { Label("Clients", systemImage: "person.2") }
            AlertSettings().tabItem { Label("Alerts & Shortcuts", systemImage: "bell.badge") }
        }
        .themed(Prefs.accent(accent))
        .frame(width: 600, height: 520)
    }
}

/// A titled M3 container for one group of settings.
struct SettingsCard<Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(palette.onSurface)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.surfaceContainer))
    }
}

struct SettingsPage<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(20)
        }
        .background(palette.surface)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @ObservedObject private var updater = Updater.shared
    @AppStorage(Prefs.autoUpdateKey) private var autoUpdate = true

    var body: some View {
        SettingsPage {
            SettingsCard(title: "Strata \(updater.current)", subtitle: "Works offline. Your files never leave this Mac; the only network call is the update check.") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        if updater.updateAvailable, let v = updater.latest?.version {
                            Text("Version \(v) is available").font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.primary)
                        }
                        if let m = updater.message {
                            Text(m).font(.system(size: 12)).foregroundStyle(palette.onSurfaceVariant)
                        }
                        Text("Build \(updater.build)").font(.system(size: 11)).foregroundStyle(palette.onSurfaceVariant)
                    }
                    Spacer()
                    if updater.updateAvailable {
                        Button(updater.downloading ? "Downloading…" : "Download & install") { Task { await updater.downloadAndOpen() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(updater.downloading)
                    } else {
                        Button(updater.checking ? "Checking…" : "Check for updates") { Task { await updater.check() } }
                            .disabled(updater.checking)
                    }
                }
                if updater.updateAvailable, let notes = updater.latest?.notes, !notes.isEmpty {
                    Text(notes).font(.system(size: 12)).foregroundStyle(palette.onSurfaceVariant)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.surfaceContainerHigh))
                }
                Toggle("Check for updates automatically (once a day)", isOn: $autoUpdate)
            }
            SettingsCard(title: "Index health", subtitle: "What Strata could and couldn't read on the last scan.") {
                IndexHealthView()
                Button("Scan now") { library.rescan() }.disabled(library.isScanning)
            }
            SettingsCard(title: "Watched folders", subtitle: "Strata reads these folders and everything inside. It only changes a file when you ask: a status tag, or Move to Trash after you confirm.") {
                ForEach(library.folders, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(palette.primary)
                        Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button("Remove") { library.removeFolder(url) }.buttonStyle(.link)
                    }
                }
                Button { addFolder() } label: { Label("Add folder…", systemImage: "plus") }
            }
            SettingsCard(title: "Skipped folders", subtitle: "App data, renders and caches you told Strata to ignore.") {
                if library.overrides.hiddenFolders.isEmpty {
                    Text("None. Right-click a folder in the sidebar to skip it.").font(.system(size: 12.5)).foregroundStyle(palette.onSurfaceVariant)
                }
                ForEach(library.overrides.hiddenFolders, id: \.self) { path in
                    HStack {
                        Image(systemName: "eye.slash").foregroundStyle(palette.onSurfaceVariant)
                        Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 13))
                        Spacer()
                        Button("Scan again") { library.unhideFolder(path) }.buttonStyle(.link)
                    }
                }
                Button { skipFolder() } label: { Label("Skip a folder…", systemImage: "eye.slash") }
            }
            SettingsCard(title: "Startup") {
                Toggle("Open Strata when you log in (lives in the menu bar)", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            library.show("Couldn't change login item: \(error.localizedDescription)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        if panel.runModal() == .OK { panel.urls.forEach(library.addFolder) }
    }

    private func skipFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Skip"
        panel.message = "Strata will ignore this folder and everything inside it."
        if panel.runModal() == .OK, let url = panel.url { library.hideFolder(url.path) }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(\.palette) private var palette
    @AppStorage(Prefs.appearanceKey) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(Prefs.accentKey) private var accent = 0
    @AppStorage(Prefs.artworkColorsKey) private var artworkColors = true
    @AppStorage(Prefs.reduceMotionKey) private var reduceMotion = false

    var body: some View {
        SettingsPage {
            SettingsCard(title: "Mode", subtitle: "Light, dark, or follow macOS.") {
                ButtonGroup(items: AppearanceMode.allCases.map { ($0.rawValue, $0.rawValue, $0.symbol) }, selection: $appearance)
                    .onChange(of: appearance) { Prefs.applyAppearance(appearance) }
                HStack(spacing: 12) {
                    preview(dark: false, label: "Light")
                    preview(dark: true, label: "Dark")
                }
            }
            SettingsCard(title: "Accent", subtitle: "The app's own colour: sidebar, buttons, Settings.") {
                HStack(spacing: 14) {
                    ForEach(Prefs.accents.indices, id: \.self) { i in
                        let on = accent == i
                        Button {
                            withAnimation(Motion.standard) { accent = i }
                        } label: {
                            VStack(spacing: 6) {
                                MorphShape(from: .circle, to: .cookie9, progress: on ? 1 : 0)
                                    .fill(Prefs.accents[i].seed.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .black))
                                        .foregroundStyle(.white).opacity(on ? 1 : 0))
                                Text(Prefs.accents[i].name).font(.system(size: 11, weight: on ? .bold : .medium))
                                    .foregroundStyle(on ? palette.onSurface : palette.onSurfaceVariant)
                            }
                        }
                        .buttonStyle(PressScale())
                    }
                }
                Toggle("Colour each client and project from its own artwork", isOn: $artworkColors)
            }
            SettingsCard(title: "Motion") {
                Toggle("Reduce motion (no springs, shorter transitions)", isOn: $reduceMotion)
            }
        }
    }

    private func preview(dark: Bool, label: String) -> some View {
        let p = Palette(seed: Prefs.accent(accent), dark: dark)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6).fill(p.surfaceContainerHigh).frame(width: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(p.onSurface).frame(width: 60, height: 7)
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 8).fill(p.primaryContainer)
                        RoundedRectangle(cornerRadius: 8).fill(p.tertiaryContainer)
                    }
                    Capsule().fill(p.primary).frame(width: 48, height: 14)
                }
            }
            .padding(8)
            .frame(height: 96)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.outlineVariant))
            Text(label).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Clients

private struct ClientSettings: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    @ViewState private var confirmReset = false

    var body: some View {
        SettingsPage {
            SettingsCard(title: "Hidden clients", subtitle: "Folders you hid from Your work. Their files are still scanned.") {
                if library.hiddenCollections.isEmpty {
                    Text("None. Right-click a client to hide it.").font(.system(size: 12.5)).foregroundStyle(palette.onSurfaceVariant)
                }
                ForEach(library.hiddenCollections) { c in
                    HStack(spacing: 10) {
                        ShapeAvatar(file: c.latest, name: c.name, size: 26)
                        Text(c.name).font(.system(size: 13, weight: .semibold))
                        Text("\(c.fileCount) files").font(.system(size: 11.5)).foregroundStyle(palette.onSurfaceVariant)
                        Spacer()
                        Button("Show again") { library.unhide(c) }.buttonStyle(.link)
                    }
                }
            }
            SettingsCard(title: "Your corrections",
                         subtitle: "Moves, merges, renames and notes you made. They always win over automatic grouping.") {
                let o = library.overrides
                Text("\(o.links.count + o.clientLinks.count) moves · \(o.detached.count + o.clientDetached.count) removals · \(o.projectNames.count + o.clientNames.count) renames · \(o.notes.count) notes")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                Button("Reset all corrections…", role: .destructive) { confirmReset = true }
                    .disabled(o.isEmpty)
                    .confirmationDialog("Reset every correction?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { library.resetCorrections() }
                    } message: {
                        Text("Moves, renames, hidden clients and notes go back to automatic. Your files are not touched.")
                    }
            }
        }
    }
}

// MARK: - Alerts & shortcuts

private struct AlertSettings: View {
    @Environment(\.palette) private var palette
    @AppStorage(Prefs.crashAlertsKey) private var crashAlerts = true
    @AppStorage(Prefs.hotkeyKey) private var hotkey = true
    @ObservedObject private var hotKey = HotKey.shared

    var body: some View {
        SettingsPage {
            SettingsCard(title: "Crash alerts",
                         subtitle: "When Illustrator or Photoshop saves a “(Recovered)” file, Strata tells you which version came before it.") {
                Toggle("Notify me about recovered files", isOn: $crashAlerts)
                    .onChange(of: crashAlerts) { if crashAlerts { Library.requestNotificationPermission() } }
            }
            SettingsCard(title: "Find anything, from any app",
                         subtitle: "A floating search like Spotlight: type a client or project, press Return to open its newest file.") {
                Toggle("Global shortcut", isOn: $hotkey)
                    .onChange(of: hotkey) { hotKey.setEnabled(hotkey) }
                HStack(spacing: 12) {
                    ShortcutRecorder()
                    if hotkey && !hotKey.registered {
                        Label("Another app already uses this shortcut. Record a different one.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(palette.warning)
                    } else if hotkey {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(palette.primary)
                    }
                }
                .disabled(!hotkey)
                Text("Works whenever Strata is running (it stays in the menu bar). Turn on “Open Strata when you log in” in General so it's always ready. Inside Strata, ⌘K also works.")
                    .font(.system(size: 12)).foregroundStyle(palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsCard(title: "Status tags",
                         subtitle: "Draft, In Review, Sent, Approved and Final are saved as Finder tags, so Finder, Spotlight and other apps see them too.") {
                Text("Set a status from a version's details panel or right-click menu.")
                    .font(.system(size: 12)).foregroundStyle(palette.onSurfaceVariant)
            }
        }
    }
}

/// Click, then press the new combination (needs ⌘, ⌥ or ⌃). Esc cancels.
struct ShortcutRecorder: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var hotKey = HotKey.shared
    @ViewState private var recording = false
    @ViewState private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press a shortcut…" : hotKey.shortcut.display)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 16).frame(minWidth: 150).frame(height: 38)
                    .background(Capsule().fill(recording ? palette.primaryContainer : palette.surfaceContainerHighest))
                    .overlay(Capsule().stroke(recording ? palette.primary : .clear, lineWidth: 2))
                    .foregroundStyle(recording ? palette.onPrimaryContainer : palette.onSurface)
            }
            .buttonStyle(PressScale())
            .help("Click, then press the keys you want")
            if hotKey.shortcut != .defaultSearch && !recording {
                Button("Reset") { hotKey.change(to: .defaultSearch) }.buttonStyle(.link)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }                    // esc cancels
            if let s = Shortcut(event: event) { hotKey.change(to: s); stop() }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Last scan, unreadable folders, what was skipped, failed previews, stale corrections.
struct IndexHealthView: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette

    var body: some View {
        let h = library.health
        let failedPreviews = ThumbnailStore.shared.failed.count
        VStack(alignment: .leading, spacing: 9) {
            line("checkmark.circle.fill", palette.primary,
                 h.lastScan.map { "Last scan \(Format.ago($0)) · \(h.files.formatted()) design files · \(String(format: "%.1f", h.duration)) s" } ?? "Not scanned yet")
            if h.unreadable.isEmpty {
                line("lock.open.fill", palette.primary, "Every watched folder is readable")
            } else {
                line("lock.fill", palette.warning, "\(h.unreadable.count) folder\(h.unreadable.count == 1 ? "" : "s") couldn't be read. Allow access in System Settings › Privacy & Security › Files and Folders.")
                ForEach(h.unreadable.prefix(5), id: \.self) { path in
                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.onSurfaceVariant)
                        .padding(.leading, 26).lineLimit(1).truncationMode(.middle)
                }
            }
            line("chevron.left.forwardslash.chevron.right", palette.onSurfaceVariant,
                 "Skipped \(h.codeProjects) code project\(h.codeProjects == 1 ? "" : "s") and \(h.sequenceFiles) rendered frames (not design work)")
            line("photo", failedPreviews > 0 ? palette.warning : palette.onSurfaceVariant,
                 failedPreviews > 0 ? "\(failedPreviews) files have no preview (macOS can't draw them; they still open normally)" : "All previews drawn so far")
            if h.missingCorrections > 0 {
                line("exclamationmark.triangle.fill", palette.warning,
                     "\(h.missingCorrections) of your corrections point to files that were moved or deleted")
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(palette.onSurface)
    }

    private func line(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
