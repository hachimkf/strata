import Foundation

/// The kinds of files Strata tracks. Anything else is ignored by the scanner.
public enum FileKind: String, Codable, CaseIterable, Sendable {
    case illustrator, photoshop, indesign, afterEffects, premiere
    case pdf, image, vector, video

    public static func from(extension ext: String) -> FileKind? {
        switch ext.lowercased() {
        case "ai", "eps", "ait": return .illustrator
        case "psd", "psb": return .photoshop
        case "indd": return .indesign
        case "aep", "aet": return .afterEffects
        case "prproj": return .premiere
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "tif", "tiff", "gif", "webp", "heic": return .image
        case "svg": return .vector
        case "mp4", "mov", "m4v": return .video
        default: return nil
        }
    }

    /// Working files you edit. Everything else is treated as an output (export / render).
    public var isSource: Bool {
        switch self {
        case .illustrator, .photoshop, .indesign, .afterEffects, .premiere: return true
        default: return false
        }
    }

    public var isVideoFamily: Bool {
        switch self {
        case .afterEffects, .premiere, .video: return true
        default: return false
        }
    }

    /// XMP is only worth looking for in formats Adobe apps write it into.
    public var mayContainXMP: Bool { self != .vector }

    public var label: String {
        switch self {
        case .illustrator: return "Illustrator"
        case .photoshop: return "Photoshop"
        case .indesign: return "InDesign"
        case .afterEffects: return "After Effects"
        case .premiere: return "Premiere Pro"
        case .pdf: return "PDF"
        case .image: return "Image"
        case .vector: return "SVG"
        case .video: return "Video"
        }
    }
}
