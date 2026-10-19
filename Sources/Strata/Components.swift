import SwiftUI
import StrataCore

// M3 Expressive components, drawn for macOS.

// MARK: - Shape library

/// A shape from the M3 Expressive library, described in polar form so any two can morph into each other.
struct ShapeSpec: Equatable {
    var lobes: Double
    var depth: Double
    var squareness: Double = 0   // 0 round lobes, 1 softly squared (for "soft square" and "pill-ish")

    static let circle = ShapeSpec(lobes: 0, depth: 0)
    static let cookie9 = ShapeSpec(lobes: 9, depth: 0.16)
    static let cookie6 = ShapeSpec(lobes: 6, depth: 0.2)
    static let clover4 = ShapeSpec(lobes: 4, depth: 0.32)
    static let sunny = ShapeSpec(lobes: 12, depth: 0.1)
    static let flower = ShapeSpec(lobes: 8, depth: 0.28)
    static let softSquare = ShapeSpec(lobes: 4, depth: 0.0, squareness: 1)

    /// The decorative set used for avatars, chosen by name so a client always keeps its shape.
    static let avatarSet: [ShapeSpec] = [.cookie9, .clover4, .sunny, .flower, .cookie6, .softSquare]

    static func forName(_ name: String) -> ShapeSpec {
        var h: UInt64 = 1469598103934665603
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return avatarSet[Int(h % UInt64(avatarSet.count))]
    }

    func radius(_ t: Double) -> Double {
        let lobe = 1 - depth / 2 + depth / 2 * cos(lobes * t)
        guard squareness > 0 else { return lobe }
        // Superellipse: a square with very round corners.
        let n = 4.0
        let c = abs(cos(t)), s = abs(sin(t))
        let square = pow(pow(c, n) + pow(s, n), -1 / n)
        return lobe * (1 - squareness) + square * squareness * 0.92
    }
}

/// Morphs between two library shapes (`progress` 0 → `from`, 1 → `to`).
struct MorphShape: Shape {
    var from: ShapeSpec
    var to: ShapeSpec
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        let steps = 200
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let k = from.radius(t) * (1 - progress) + to.radius(t) * progress
            let pt = CGPoint(x: c.x + r * k * cos(t - .pi / 2), y: c.y + r * k * sin(t - .pi / 2))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// M3 Expressive loading indicator: a shape that keeps morphing and turning.
struct MorphingLoader: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 44
    @ViewState private var step = 0
    @ViewState private var progress = 0.0
    @ViewState private var angle = 0.0
    private let sequence: [ShapeSpec] = [.cookie9, .clover4, .sunny, .flower, .cookie6, .softSquare]

    var body: some View {
        MorphShape(from: sequence[step % sequence.count], to: sequence[(step + 1) % sequence.count], progress: progress)
            .fill(palette.primary)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .task {
                while !Task.isCancelled {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                        progress = 1
                        angle += 70
                    }
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    step += 1
                    progress = 0
                }
            }
    }
}

/// A thumbnail cropped into a library shape: clients get a recognisable silhouette.
struct ShapeAvatar: View {
    let file: CreativeFile?
    let name: String
    var size: CGFloat = 26

    var body: some View {
        let spec = ShapeSpec.forName(name)
        ZStack {
            if let file { Thumbnail(file: file, side: size * 3) }
        }
        .frame(width: size, height: size)
        .clipShape(MorphShape(from: spec, to: spec, progress: 0))
    }
}

// MARK: - Button group (connected, the selected one turns into a pill)

struct ButtonGroup<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    let items: [(value: Value, title: String, symbol: String?)]
    @Binding var selection: Value
    var height: CGFloat = 36

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let on = item.value == selection
                Button {
                    withAnimation(Motion.fast) { selection = item.value }
                } label: {
                    HStack(spacing: 6) {
                        if let symbol = item.symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)) }
                        Text(item.title).font(.system(size: 12.5, weight: on ? .heavy : .semibold))
                    }
                    .padding(.horizontal, on ? 16 : 12)
                    .frame(height: height)
                    .background(segmentShape(i, on: on).fill(on ? palette.primary : palette.surfaceContainerHighest))
                    .foregroundStyle(on ? palette.onPrimary : palette.onSurfaceVariant)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
            }
        }
    }

    /// Outer ends are round, inner joins are tight, and the selected segment becomes a full pill.
    private func segmentShape(_ i: Int, on: Bool) -> UnevenRoundedRectangle {
        let full = height / 2, inner: CGFloat = 6
        let leading = on || i == 0 ? full : inner
        let trailing = on || i == items.count - 1 ? full : inner
        return UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                      bottomTrailingRadius: trailing, topTrailingRadius: trailing, style: .continuous)
    }
}

// MARK: - Split button

struct SplitButton<MenuContent: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let symbol: String
    let action: () -> Void
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: 3) {
            Button(action: action) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 20).padding(.trailing, 14).frame(height: 44)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22,
                                                       bottomTrailingRadius: 6, topTrailingRadius: 6, style: .continuous)
                        .fill(palette.primary))
                    .foregroundStyle(palette.onPrimary)
            }
            .buttonStyle(PressScale())
            Menu {
                menu()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .heavy))
                    .frame(width: 38, height: 44)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6,
                                                       bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous)
                        .fill(palette.primary))
                    .foregroundStyle(palette.onPrimary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Extended FAB

struct ExtendedFAB: View {
    @Environment(\.palette) private var palette
    let title: String
    let symbol: String
    var shortcut: String? = nil
    /// Compact: a small round button that shows its label only while hovered.
    var compact = false
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        let expanded = !compact || hovering
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: compact ? 15 : 16, weight: .heavy))
                if expanded { Text(title).font(.system(size: 14.5, weight: .heavy)).lineLimit(1).fixedSize() }
                if expanded, let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11.5, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(palette.onTertiaryContainer.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, expanded ? 22 : 0).frame(minWidth: compact ? 46 : 56).frame(height: compact ? 46 : 56)
            .background(MorphRect(radius: compact ? 23 : (hovering ? 28 : 18)).fill(palette.tertiaryContainer))
            .foregroundStyle(palette.onTertiaryContainer)
            .shadow(color: .black.opacity(0.18), radius: hovering ? 18 : 10, y: hovering ? 8 : 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .onHover { h in withAnimation(Motion.fast) { hovering = h } }
    }
}

// MARK: - Toast (M3 snackbar)

struct Toast: View {
    @Environment(\.palette) private var palette
    let message: String
    var undo: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.primary)
            Text(message).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            if let undo {
                Button("Undo", action: undo)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.primary)
                    .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(Capsule().fill(palette.onSurface))
        .foregroundStyle(palette.surface)
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
    }
}

// MARK: - Text prompt sheet (rename)

struct NamePrompt: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initial: String
    let save: (String) -> Void
    @ViewState private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.display(20))
            TextField("Name", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 16).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.surfaceContainerHigh))
                .onSubmit { save(text); dismiss() }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { text = initial }
    }
}

// MARK: - Picker sheet (move to project / client)

struct PickItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let file: CreativeFile?
}

struct PickerSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let title: String
    let items: [PickItem]
    let pick: (PickItem) -> Void
    @ViewState private var query = ""

    private var filtered: [PickItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? items : items.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.display(20))
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16).frame(height: 40)
                .background(Capsule().fill(palette.surfaceContainerHigh))
            List(filtered) { item in
                Button {
                    pick(item)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        ShapeAvatar(file: item.file, name: item.title, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
            .frame(height: 340)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

// MARK: - Scroll edge fade

/// A soft blur that fades in towards the bottom edge, so content scrolls away under it instead of being cut.
struct ScrollFade: ViewModifier {
    @Environment(\.palette) private var palette
    var height: CGFloat
    var tinted: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                // Kept subtle: a hint that there's more below, not a curtain.
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                if tinted {
                    LinearGradient(colors: [palette.surface.opacity(0), palette.surface.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(height: height)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func scrollFade(height: CGFloat = 44, tinted: Bool = true) -> some View { modifier(ScrollFade(height: height, tinted: tinted)) }
}

// MARK: - Floating back button

/// Back pill that floats over scrolling content (frosted, always reachable). ⌘[ also works.
struct FloatingBack: View {
    @Environment(\.palette) private var palette
    let title: String
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.left")
                .font(.system(size: 12.5, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 14).frame(height: 34)
                .background(.regularMaterial, in: Capsule())
                .background(palette.surfaceContainerHigh.opacity(hovering ? 0.9 : 0.5), in: Capsule())
                .overlay(Capsule().stroke(palette.outlineVariant.opacity(0.6), lineWidth: 1))
                .foregroundStyle(palette.onSurface)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .fixedSize()
        }
        .buttonStyle(PressScale())
        .keyboardShortcut("[", modifiers: .command)
        .onHover { h in withAnimation(Motion.fast) { hovering = h } }
        .help("Back to \(title) (⌘[)")
    }
}
