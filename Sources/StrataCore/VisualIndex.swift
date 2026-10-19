import Foundation
import Vision
import ImageIO
import CoreGraphics
import AVFoundation

/// Visual fingerprints of artwork (Apple Vision feature prints), cached on disk by path + date.
/// Used to put a project that belongs to no client next to the client whose work it looks like.
public final class VisualIndex: @unchecked Sendable {
    private var prints: [String: Data] = [:]   // "path#mtime" → archived VNFeaturePrintObservation
    private var decoded: [String: VNFeaturePrintObservation] = [:]
    private let lock = NSLock()
    private let fileURL: URL?
    private var dirty = false

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let map = try? PropertyListDecoder().decode([String: Data].self, from: data) {
            prints = map
        }
    }

    public static func defaultURL() -> URL {
        MetadataCache.defaultURL().deletingLastPathComponent().appendingPathComponent("visual-cache-v1.plist")
    }

    public func save() {
        lock.lock(); defer { lock.unlock() }
        guard dirty, let fileURL, let data = try? PropertyListEncoder().encode(prints) else { return }
        SecureStore.write(data, to: fileURL)
        dirty = false
    }

    static func canRender(_ kind: FileKind) -> Bool {
        switch kind {
        case .image, .photoshop, .pdf, .illustrator, .video: return true
        default: return false
        }
    }

    /// The fingerprint of a file, computed once and cached.
    public func print(for file: CreativeFile) -> VNFeaturePrintObservation? {
        guard Self.canRender(file.kind) else { return nil }
        let key = "\(file.path)#\(Int(file.modified.timeIntervalSince1970))"
        lock.lock()
        if let hit = decoded[key] { lock.unlock(); return hit }
        if let data = prints[key],
           let obs = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data) {
            decoded[key] = obs
            lock.unlock()
            return obs
        }
        lock.unlock()

        guard let image = Self.render(file) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let obs = request.results?.first else { return nil }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
        lock.lock()
        decoded[key] = obs
        if let data { prints[key] = data; dirty = true }
        lock.unlock()
        return obs
    }

    public static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        guard (try? a.computeDistance(&d, to: b)) != nil else { return nil }
        return d
    }

    /// A small bitmap of the file's first page / frame.
    static func render(_ file: CreativeFile, side: Int = 300) -> CGImage? {
        let url = file.url
        switch file.kind {
        case .pdf, .illustrator:
            guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) else { return nil }
            let box = page.getBoxRect(.cropBox)
            guard box.width > 0, box.height > 0 else { return nil }
            let scale = CGFloat(side) / max(box.width, box.height)
            let w = Int(box.width * scale), h = Int(box.height * scale)
            guard let ctx = CGContext(data: nil, width: max(w, 1), height: max(h, 1), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
            return ctx.makeImage()
        case .video:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: side, height: side)
            return try? generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
        default:
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }
    }
}

/// Suggests which client an orphan project belongs to, by how much its artwork looks like each client's.
public enum VisualMatcher {
    public struct Match: Sendable {
        public let orphanPath: String
        public let clientAnchorPath: String
        public let clientName: String
        public let distance: Float
        public let runnerUp: Float
    }

    /// Distance below which two pieces of artwork count as "the same visual family"
    /// (tuned on real client work: true matches < 0.45, unrelated work > 0.6).
    public static var threshold: Float = 0.5
    /// The best client must be clearly closer than the second best.
    public static var margin: Float = 0.8

    /// Stray projects and small client fragments, matched against the big clients.
    public static func suggest(_ catalog: Catalog, index: VisualIndex, referencesPerClient: Int = 24) -> [Match] {
        let big = catalog.collections.filter { $0.fileCount >= Collector.smallClientFiles }
        var refs: [(client: Collection, prints: [VNFeaturePrintObservation])] = []
        for c in big {
            let files = c.recentFiles.filter { VisualIndex.canRender($0.kind) }.prefix(referencesPerClient)
            let p = files.compactMap { index.print(for: $0) }
            if !p.isEmpty { refs.append((c, p)) }
        }
        guard !refs.isEmpty else { return [] }

        // Each orphan: (a file inside it, a few of its newest renderable files).
        var orphans: [(path: String, files: [CreativeFile])] = catalog.standalone.map { p in
            (p.first.file.path, Array(p.versions.reversed().map(\.file).filter { VisualIndex.canRender($0.kind) }.prefix(3)))
        }
        for c in catalog.collections where c.fileCount < Collector.smallClientFiles {
            if let any = c.allFiles.first {
                orphans.append((any.path, Array(c.recentFiles.filter { VisualIndex.canRender($0.kind) }.prefix(4))))
            }
        }

        var out: [Match] = []
        for orphan in orphans {
            let own = orphan.files.compactMap { index.print(for: $0) }
            guard !own.isEmpty else { continue }
            var scores: [(Collection, Float)] = []
            for (client, prints) in refs {
                var best = Float.greatestFiniteMagnitude
                for a in own { for b in prints { if let d = VisualIndex.distance(a, b), d < best { best = d } } }
                scores.append((client, best))
            }
            scores.sort { $0.1 < $1.1 }
            guard let first = scores.first, let anchor = first.0.allFiles.first else { continue }
            let second = scores.count > 1 ? scores[1].1 : Float.greatestFiniteMagnitude
            if first.1 <= threshold && first.1 <= second * margin {
                out.append(Match(orphanPath: orphan.path, clientAnchorPath: anchor.path,
                                 clientName: first.0.name, distance: first.1, runnerUp: second))
            }
        }
        index.save()
        return out
    }
}
