import Foundation

/// Strata's own data (metadata cache, corrections, visual fingerprints) lists your file paths and notes,
/// so it is written atomically and readable by your user account only.
public enum SecureStore {
    public static func write(_ data: Data, to url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        guard (try? data.write(to: url, options: [.atomic])) != nil else { return }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
