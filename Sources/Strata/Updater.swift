import SwiftUI
import AppKit
import CryptoKit

/// Checks the public releases repo for a newer Strata, downloads the DMG over HTTPS,
/// verifies its SHA-256 against the checksum published with the release, then opens it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let owner = "hachimkf"
    static let repo = "strata-releases"
    private static let lastCheckKey = "lastUpdateCheck"

    struct Release: Equatable {
        let version: String
        let notes: String
        let dmg: URL
        let checksum: URL?
        let page: URL
    }

    @Published private(set) var latest: Release?
    @Published private(set) var checking = false
    @Published private(set) var downloading = false
    @Published private(set) var message: String?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    var updateAvailable: Bool { latest.map { Self.isNewer($0.version, than: current) } ?? false }

    /// At launch: at most once a day, and only if the user allows it.
    func checkIfDue(notify: @escaping (String) -> Void) {
        guard UserDefaults.standard.bool(forKey: Prefs.autoUpdateKey) else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        Task {
            await check()
            if updateAvailable, let v = latest?.version { notify("Strata \(v) is available · Settings › General") }
        }
    }

    func check() async {
        checking = true
        defer { checking = false }
        message = nil
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        guard let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Strata/\(current)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
                  let assets = json["assets"] as? [[String: Any]] else {
                message = "No release published yet."
                return
            }
            func asset(_ suffix: String) -> URL? {
                assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
                    .flatMap { $0["browser_download_url"] as? String }
                    .flatMap(URL.init(string:))
                    .flatMap { Self.trusted($0) ? $0 : nil }
            }
            guard let dmg = asset(".dmg") else { message = "The latest release has no installer."; return }
            latest = Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                             notes: json["body"] as? String ?? "", dmg: dmg, checksum: asset(".sha256"), page: page)
            message = updateAvailable ? nil : "You're up to date (\(current))."
        } catch {
            message = "Couldn't check for updates: \(error.localizedDescription)"
        }
    }

    func downloadAndOpen() async {
        guard let release = latest else { return }
        downloading = true
        defer { downloading = false }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: release.dmg)
            if let checksumURL = release.checksum {
                let (sumData, _) = try await URLSession.shared.data(from: checksumURL)
                let expected = String(decoding: sumData, as: UTF8.self).split(separator: " ").first.map(String.init)?.lowercased() ?? ""
                let actual = try Self.sha256(of: tmp)
                guard !expected.isEmpty, expected == actual else {
                    try? FileManager.default.removeItem(at: tmp)
                    message = "The download didn't match its checksum, so it was discarded."
                    return
                }
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let target = downloads.appendingPathComponent("Strata-\(release.version).dmg")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: tmp, to: target)
            message = "Downloaded. Drag Strata into Applications to replace this version, then reopen it."
            NSWorkspace.shared.open(target)
        } catch {
            message = "Download failed: \(error.localizedDescription)"
        }
    }

    /// Only GitHub over HTTPS.
    static func trusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// "1.10.0" > "1.9.2"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
