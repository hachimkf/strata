import SwiftUI
import AppKit

/// Full Disk Access: one switch in System Settings (confirmed with Touch ID or your password)
/// instead of a prompt for every folder. Apps can't grant it to themselves; Strata only checks and guides.
@MainActor
final class DiskAccess: ObservableObject {
    static let shared = DiskAccess()
    @Published private(set) var granted = DiskAccess.check()
    private var observer: Any?

    init() {
        // Re-check whenever the user comes back from System Settings.
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in DiskAccess.shared.refresh() }
        }
    }

    func refresh() { granted = Self.check() }

    /// These files can only be opened by apps with Full Disk Access. Nothing is read: just opened and closed.
    nonisolated static func check() -> Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
            NSHomeDirectory() + "/Library/Mail",
        ]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue { return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil }
            if let handle = FileHandle(forReadingAtPath: path) { try? handle.close(); return true }
            return false
        }
        return false
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS applies Full Disk Access to newly started processes, so Strata restarts itself.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// The one-time card: what Full Disk Access means here, and the three steps.
struct AccessCard: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var access = DiskAccess.shared
    @AppStorage("accessCardDismissed") private var dismissed = false
    var alwaysShow = false

    var body: some View {
        if !access.granted && (alwaysShow || !dismissed) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(palette.primary, in: Circle())
                        .foregroundStyle(palette.onPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow access once").font(.display(20)).foregroundStyle(palette.onSurface)
                        Text("Give Strata Full Disk Access and macOS stops asking about each folder. Strata still only looks at your work folders (Desktop, Documents, Downloads, Movies and any you add) and never at system files.")
                            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if !alwaysShow {
                        Button { dismissed = true } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                            .buttonStyle(.plain).foregroundStyle(palette.onSurfaceVariant).help("Not now (Settings › General keeps this)")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Open System Settings › Privacy & Security › Full Disk Access.")
                    step(2, "Switch on Strata and confirm with Touch ID or your password. If Strata isn't listed, click + and choose it in Applications.")
                    step(3, "Come back and restart Strata.")
                }
                HStack(spacing: 10) {
                    Button { DiskAccess.openSettings() } label: {
                        Label("Open System Settings", systemImage: "gearshape.fill")
                            .font(.system(size: 13, weight: .bold)).fixedSize()
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(palette.primary, in: Capsule())
                            .foregroundStyle(palette.onPrimary)
                    }
                    .buttonStyle(PressScale())
                    Button { DiskAccess.relaunch() } label: {
                        Label("Restart Strata", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold)).fixedSize()
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(palette.secondaryContainer, in: Capsule())
                            .foregroundStyle(palette.onSecondaryContainer)
                    }
                    .buttonStyle(PressScale())
                    Button("Show Strata in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                        .buttonStyle(.link)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.surfaceContainerLow))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(palette.primary.opacity(0.5), lineWidth: 1.5))
        } else if alwaysShow && access.granted {
            Label("Full Disk Access is on. macOS won't ask about folders.", systemImage: "checkmark.shield.fill")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(palette.primary)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 11, weight: .heavy))
                .frame(width: 20, height: 20).background(palette.secondaryContainer, in: Circle())
                .foregroundStyle(palette.onSecondaryContainer)
            Text(text).font(.system(size: 12.5)).foregroundStyle(palette.onSurface).fixedSize(horizontal: false, vertical: true)
        }
    }
}
