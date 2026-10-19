import SwiftUI
import AppKit
import StrataCore

// Material 3 Expressive, the Strata way: every project gets a tonal palette grown from its own artwork.

// MARK: - OKLCH colour math (perceptual, so every tone of every hue reads equally bright)

struct OKLCH: Hashable {
    var l: Double, c: Double, h: Double

    static let appSeed = OKLCH(l: 0.55, c: 0.19, h: 292)   // electric violet

    init(l: Double, c: Double, h: Double) { self.l = l; self.c = c; self.h = h }

    init(r: Double, g: Double, b: Double) {
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let (R, G, B) = (lin(r), lin(g), lin(b))
        let l_ = cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B)
        let m_ = cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B)
        let s_ = cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
        let L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        l = L
        c = sqrt(a * a + bb * bb)
        h = (atan2(bb, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func rgb(l L: Double, c C: Double, h: Double) -> (Double, Double, Double) {
        let a = C * cos(h * .pi / 180), b = C * sin(h * .pi / 180)
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let (l, m, s) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// sRGB components (0…1) at this tone, with chroma reduced until it fits in sRGB.
    var srgb: (r: Double, g: Double, b: Double) {
        var lo = 0.0, hi = c
        var best = OKLCH.rgb(l: l, c: 0, h: h)
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            let v = OKLCH.rgb(l: l, c: mid, h: h)
            if [v.0, v.1, v.2].allSatisfy({ $0 >= -0.0005 && $0 <= 1.0005 }) { best = v; lo = mid } else { hi = mid }
        }
        func gamma(_ x: Double) -> Double {
            let v = min(max(x, 0), 1)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return (gamma(best.0), gamma(best.1), gamma(best.2))
    }

    var color: Color {
        let v = srgb
        return Color(.sRGB, red: v.r, green: v.g, blue: v.b)
    }

    /// "#FF6B4A"
    var hex: String {
        let v = srgb
        return String(format: "#%02X%02X%02X", Int((v.r * 255).rounded()), Int((v.g * 255).rounded()), Int((v.b * 255).rounded()))
    }

    func tone(_ l: Double, chroma: Double, hueShift: Double = 0) -> Color {
        OKLCH(l: l, c: chroma, h: (h + hueShift + 360).truncatingRemainder(dividingBy: 360)).color
    }
}

// MARK: - Palette (M3 colour roles)

struct Palette {
    let seed: OKLCH
    let dark: Bool

    let primary, onPrimary, primaryContainer, onPrimaryContainer: Color
    let secondaryContainer, onSecondaryContainer: Color
    let tertiary, tertiaryContainer, onTertiaryContainer: Color
    let surface, surfaceDim, surfaceContainerLow, surfaceContainer, surfaceContainerHigh, surfaceContainerHighest: Color
    let onSurface, onSurfaceVariant, outline, outlineVariant: Color
    let warning, warningContainer, onWarningContainer: Color

    init(seed: OKLCH, dark: Bool) {
        self.seed = seed
        self.dark = dark
        let s = seed
        let vivid = min(max(s.c, 0.05), 0.2)       // keep near-greyscale artwork tasteful
        let soft = min(vivid * 0.45, 0.075)
        let tint = min(vivid * 0.12, 0.018)
        let warn = OKLCH(l: 0.7, c: 0.16, h: 62)
        if dark {
            primary = s.tone(0.80, chroma: vivid * 0.75)
            onPrimary = s.tone(0.25, chroma: soft)
            primaryContainer = s.tone(0.33, chroma: soft * 1.4)
            onPrimaryContainer = s.tone(0.92, chroma: soft)
            secondaryContainer = s.tone(0.30, chroma: soft * 0.6)
            onSecondaryContainer = s.tone(0.92, chroma: soft * 0.5)
            tertiary = s.tone(0.80, chroma: vivid * 0.7, hueShift: 70)
            tertiaryContainer = s.tone(0.33, chroma: soft * 1.3, hueShift: 70)
            onTertiaryContainer = s.tone(0.92, chroma: soft, hueShift: 70)
            surface = Color(white: 30 / 255.0)
            surfaceDim = Color(white: 26 / 255.0)
            surfaceContainerLow = Color(white: 35 / 255.0)
            surfaceContainer = Color(white: 40 / 255.0)
            surfaceContainerHigh = Color(white: 47 / 255.0)
            surfaceContainerHighest = Color(white: 55 / 255.0)
            onSurface = s.tone(0.94, chroma: tint)
            onSurfaceVariant = s.tone(0.80, chroma: tint * 1.5)
            outline = s.tone(0.58, chroma: tint * 1.5)
            outlineVariant = s.tone(0.34, chroma: tint * 1.5)
            warning = warn.tone(0.80, chroma: 0.14)
            warningContainer = warn.tone(0.34, chroma: 0.07)
            onWarningContainer = warn.tone(0.93, chroma: 0.05)
        } else {
            primary = s.tone(0.50, chroma: vivid)
            onPrimary = s.tone(0.99, chroma: 0.01)
            primaryContainer = s.tone(0.90, chroma: soft)
            onPrimaryContainer = s.tone(0.27, chroma: soft * 1.2)
            secondaryContainer = s.tone(0.915, chroma: soft * 0.5)
            onSecondaryContainer = s.tone(0.28, chroma: soft * 0.6)
            tertiary = s.tone(0.52, chroma: vivid * 0.85, hueShift: 70)
            tertiaryContainer = s.tone(0.91, chroma: soft, hueShift: 70)
            onTertiaryContainer = s.tone(0.28, chroma: soft * 1.1, hueShift: 70)
            surface = Color(white: 247 / 255.0)
            surfaceDim = Color(white: 232 / 255.0)
            surfaceContainerLow = Color(white: 242 / 255.0)
            surfaceContainer = Color(white: 236 / 255.0)
            surfaceContainerHigh = Color(white: 229 / 255.0)
            surfaceContainerHighest = Color(white: 220 / 255.0)
            onSurface = s.tone(0.21, chroma: tint)
            onSurfaceVariant = s.tone(0.43, chroma: tint * 1.4)
            outline = s.tone(0.62, chroma: tint * 1.4)
            outlineVariant = s.tone(0.87, chroma: tint * 1.2)
            warning = warn.tone(0.55, chroma: 0.15)
            warningContainer = warn.tone(0.93, chroma: 0.06)
            onWarningContainer = warn.tone(0.32, chroma: 0.08)
        }
    }

    /// File-type accent that harmonises with this palette (same tone, its own hue).
    func kind(_ ext: String) -> (fg: Color, bg: Color) {
        let hue: Double
        switch ext {
        case "AI", "EPS", "AIT", "SVG": hue = 55
        case "PSD", "PSB": hue = 245
        case "INDD": hue = 355
        case "AEP", "PRPROJ", "MP4", "MOV", "M4V": hue = 300
        case "PDF": hue = 25
        default: hue = 155
        }
        let k = OKLCH(l: 0.5, c: 0.14, h: hue)
        return dark ? (k.tone(0.85, chroma: 0.11), k.tone(0.32, chroma: 0.06))
                    : (k.tone(0.42, chroma: 0.14), k.tone(0.93, chroma: 0.045))
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(seed: .appSeed, dark: false)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Applies a palette grown from `seed`, following the system's light / dark appearance.
struct Themed: ViewModifier {
    let seed: OKLCH
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .environment(\.palette, Palette(seed: seed, dark: scheme == .dark))
            .tint(Palette(seed: seed, dark: scheme == .dark).primary)
    }
}

extension View {
    func themed(_ seed: OKLCH) -> some View { modifier(Themed(seed: seed)) }
}

// MARK: - Seed colour from artwork

enum ColorExtractor {
    /// The most characterful colour in an image: hue buckets weighted by chroma, greys ignored.
    static func seed(from image: NSImage) -> OKLCH? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = 28, h = 28
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var weight = [Double](repeating: 0, count: 24)
        var sums = [(l: Double, c: Double, x: Double, y: Double)](repeating: (0, 0, 0, 0), count: 24)
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255
            guard a > 0.5 else { continue }
            let o = OKLCH(r: Double(px[i]) / 255 / a, g: Double(px[i + 1]) / 255 / a, b: Double(px[i + 2]) / 255 / a)
            guard o.c > 0.035, o.l > 0.15, o.l < 0.97 else { continue }
            let bucket = Int(o.h / 15) % 24
            let wgt = o.c * o.c
            weight[bucket] += wgt
            sums[bucket].l += o.l * wgt
            sums[bucket].c += o.c * wgt
            sums[bucket].x += cos(o.h * .pi / 180) * wgt
            sums[bucket].y += sin(o.h * .pi / 180) * wgt
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0.02 else { return nil }
        let s = sums[best], wt = weight[best]
        let hue = (atan2(s.y, s.x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return OKLCH(l: s.l / wt, c: s.c / wt, h: hue)
    }

    /// Up to `count` distinct colours in an image (vivid ones by hue, plus a dark and a light neutral if they matter),
    /// each with its share of the image.
    static func palette(from image: NSImage, count: Int = 6) -> [(color: OKLCH, weight: Double)] {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var buckets = [String: (n: Double, l: Double, c: Double, x: Double, y: Double)]()
        var total = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255
            guard a > 0.5 else { continue }
            let o = OKLCH(r: Double(px[i]) / 255 / a, g: Double(px[i + 1]) / 255 / a, b: Double(px[i + 2]) / 255 / a)
            total += 1
            let key: String
            if o.c < 0.04 {
                guard o.l < 0.3 || o.l > 0.93 else { continue }
                key = o.l < 0.3 ? "dark" : "light"
            } else {
                key = "h\(Int(o.h / 20))-\(o.l < 0.45 ? 0 : (o.l < 0.75 ? 1 : 2))"
            }
            var b = buckets[key] ?? (0, 0, 0, 0, 0)
            b.n += 1; b.l += o.l; b.c += o.c
            b.x += cos(o.h * .pi / 180); b.y += sin(o.h * .pi / 180)
            buckets[key] = b
        }
        guard total > 0 else { return [] }
        return buckets.values
            .filter { $0.n / total > 0.02 }
            .sorted { $0.n > $1.n }
            .prefix(count)
            .map { b in
                let hue = (atan2(b.y, b.x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                return (OKLCH(l: b.l / b.n, c: b.c / b.n, h: hue), b.n / total)
            }
    }

    /// A calm, stable hue for artwork without colour (black & white logos, sketches).
    static func fallback(for name: String) -> OKLCH {
        var hash: UInt64 = 5381
        for b in name.utf8 { hash = (hash &* 33) &+ UInt64(b) }
        return OKLCH(l: 0.55, c: 0.06, h: Double(hash % 360))
    }
}

@MainActor
final class PaletteStore {
    static let shared = PaletteStore()
    private var seeds: [String: OKLCH] = [:]

    func seed(for file: CreativeFile, name: String) async -> OKLCH {
        let key = "\(file.path)#\(file.modified.timeIntervalSince1970)"
        if let s = seeds[key] { return s }
        var seed = ColorExtractor.fallback(for: name)
        if let image = await ThumbnailStore.shared.image(for: file.url, side: 96, modified: file.modified),
           let found = ColorExtractor.seed(from: image) {
            seed = found
        }
        seeds[key] = seed
        return seed
    }
}

// MARK: - Typography

extension Font {
    /// Display titles: SF Pro, bold and condensed. Editorial and confident rather than playful
    /// (M3 Expressive "emphasized" type, translated to Apple's variable font axes).
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: size >= 30 ? .heavy : .bold).width(.condensed)
    }
}

// MARK: - Expressive shapes & motion

enum Motion {
    static var reduced: Bool {
        UserDefaults.standard.bool(forKey: Prefs.reduceMotionKey) || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    /// M3 Expressive "spatial" springs, for things that move: quick, with a little overshoot.
    static var fast: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.72) }
    static var standard: Animation { reduced ? .easeOut(duration: 0.18) : .spring(response: 0.48, dampingFraction: 0.74) }
    static var gentle: Animation { reduced ? .easeOut(duration: 0.22) : .spring(response: 0.7, dampingFraction: 0.82) }
    /// M3 Expressive "effects" springs, for colour and opacity: no overshoot.
    static var effects: Animation { .easeOut(duration: reduced ? 0.12 : 0.28) }
}

/// The scalloped "cookie" from the M3 Expressive shape set. `depth` 0 is a circle, so it morphs.
struct Cookie: Shape {
    var lobes: Int = 9
    var depth: CGFloat = 0.14
    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        let steps = 180
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let radius = r * (1 - depth / 2 + depth / 2 * cos(Double(lobes) * t))
            let pt = CGPoint(x: c.x + radius * cos(t - .pi / 2), y: c.y + radius * sin(t - .pi / 2))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Rounded rectangle whose corner radius can animate (shape morph on hover).
struct MorphRect: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path { RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect) }
}

/// Small pill label: file types, states.
struct Pill: View {
    let text: String
    var fg: Color
    var bg: Color
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            if !text.isEmpty { Text(text).lineLimit(1) }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, text.isEmpty ? 6 : 9).padding(.vertical, 4)
        .fixedSize()
        .background(bg, in: Capsule())
        .foregroundStyle(fg)
    }
}

struct KindPill: View {
    @Environment(\.palette) private var palette
    let ext: String
    var body: some View {
        let k = palette.kind(ext)
        Pill(text: ext, fg: k.fg, bg: k.bg)
    }
}
