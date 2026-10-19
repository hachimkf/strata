import Foundation

/// Turns messy design file names into a comparable set of words.
///
/// `Atlas Logo final final (Recovered) 2.ai`, `atlas_logo_FINAL_v2.ai` and `atlas-logo.pdf`
/// all become `["atlas", "logo"]`.
public enum NameNormalizer {
    /// Words that describe the *state* of a file, not the project. Removed entirely.
    static let noise: Set<String> = [
        // versions & states
        "copy", "copie", "copia", "kopie", "recovered", "récupéré", "recupere", "recuperado",
        "final", "finale", "finalfinal", "def", "definitif", "définitif", "draft", "brouillon", "wip",
        "old", "new", "edit", "edited", "export", "exported", "version", "ver", "rev", "revised",
        "updated", "update", "fix", "fixed", "changes", "approved", "ok", "valide", "validé", "last",
        "latest", "master", "alt", "option", "opt", "variant", "sketch", "rough", "proof", "preview",
        "review", "feedback", "client", "test", "tmp", "temp",
        // output flavours
        "print", "web", "hd", "fhd", "uhd", "lowres", "hires", "low", "high", "res", "small", "large",
        "rgb", "cmyk", "outlined", "outline", "vectorized", "flattened", "flat", "compressed", "optimized",
        "color", "colour", "bw", "mix", "music", "sound", "nosound", "subtitles", "subs", "cut",
        // paper & format sizes
        "iso", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "letter", "tabloid", "square", "portrait", "landscape",
        "vertical", "horizontal", "us", "uk", "eu",
        // glue words
        "the", "and", "for", "with", "de", "la", "le", "les", "du", "des", "et", "pour", "en",
    ]

    /// Generic words that are fine inside a name but can't identify a project on their own
    /// (otherwise every `Untitled-1.ai` and `Screenshot …png` would become one giant project).
    public static let weak: Set<String> = [
        "untitled", "sans", "titre", "unbenannt", "sin", "titulo", "artboard", "plan", "image", "img",
        "dsc", "pxl", "screenshot", "capture", "screen", "shot", "photo", "pic", "video", "vid", "movie",
        "logo", "poster", "flyer", "banner", "post", "story", "stories", "instagram", "insta", "facebook",
        "cover", "mockup", "design", "file", "document", "doc", "scan", "at", "pm", "am", "project",
        "sequence", "comp", "render", "clip", "frame", "layer", "template", "asset", "assets", "icon",
        "icons", "page", "pages", "card", "social", "reel", "edit", "jan", "feb", "mar", "apr", "may",
        "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec", "whatsapp", "whats", "app", "download",
        "downloads", "chat", "gpt", "chatgpt", "gemini", "generated", "midjourney", "dalle", "firefly",
        "ai", "ad", "ads", "recording", "recordings", "record", "enregistrement", "ecran", "camera", "pexels", "unsplash", "freepik", "shutterstock", "adobestock", "stock",
    ]

    /// Ordered, de-duplicated words of a file name with noise removed.
    public static func tokens(for fileName: String) -> [String] {
        var base = (fileName as NSString).deletingPathExtension
        // Split camelCase before lowercasing: "AtlasLogo" -> "Atlas Logo".
        base = base.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        base = base.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let raw = base.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        var seen = Set<String>()
        var out: [String] = []
        for var t in raw {
            if t.range(of: "^(v|ver|rev|r|vf)\\d+$", options: .regularExpression) != nil { continue }
            if t.range(of: "^\\d+(px|x|p|k|mm|cm|in)?$", options: .regularExpression) != nil { continue }
            if t.range(of: "^\\d+x\\d+(px|mm|cm|in)?$", options: .regularExpression) != nil { continue }   // 11x14, 1080x1920
            // "final2" -> "final", "logo03" -> "logo"
            if let r = t.range(of: "\\d+$", options: .regularExpression), t.distance(from: t.startIndex, to: r.lowerBound) >= 2 {
                t.removeSubrange(r)
            }
            guard t.count >= 2, !noise.contains(t), seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return out
    }

    /// Words specific enough to identify a project: not generic, at least 3 characters.
    public static func strongTokens(_ tokens: [String]) -> [String] { tokens.filter { $0.count >= 3 && !weak.contains($0) } }

    /// Order-independent key used for exact name matches. Nil when the name is too generic to trust.
    public static func key(for fileName: String) -> String? {
        let t = tokens(for: fileName)
        guard !strongTokens(t).isEmpty else { return nil }
        return t.sorted().joined(separator: " ")
    }

    /// Jaccard similarity of the two token sets, 0 when they share no strong word.
    public static func similarity(_ a: [String], _ b: [String]) -> Double {
        let sa = Set(a), sb = Set(b)
        guard !sa.isEmpty, !sb.isEmpty else { return 0 }
        guard !Set(strongTokens(a)).isDisjoint(with: strongTokens(b)) else { return 0 }
        return Double(sa.intersection(sb).count) / Double(sa.union(sb).count)
    }

    /// Folder names that organise work but don't name a project ("2_Photos", "Clients", "TO_UPLOAD").
    static let genericFolderWords: Set<String> = [
        "photos", "images", "exports", "digital", "files", "upload", "these", "to", "clients", "work",
        "projects", "jobs", "archive", "archives", "source", "sources", "working", "links", "fonts",
        "documents", "downloads", "desktop", "movies", "pictures", "renders", "output", "outputs",
        "deliverables", "mockups", "art", "prints", "misc", "stuff", "folder", "dossier", "travail",
        "projets", "projet", "fichiers", "originals", "original", "raw", "jpg", "png", "pdf", "psd",
    ]

    /// Specific words of a folder name, or empty when the folder is just an organiser.
    public static func folderTokens(for folderName: String) -> [String] {
        strongTokens(tokens(for: folderName + ".x")).filter { !genericFolderWords.contains($0) }
    }

    /// "atlas logo" -> "Atlas Logo"
    public static func displayName(from tokens: [String]) -> String {
        tokens.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
