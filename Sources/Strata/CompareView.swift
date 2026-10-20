import SwiftUI
import AppKit
import StrataCore

enum CompareMode: String, CaseIterable { case side = "Side by side", slider = "Slider", overlay = "Overlay", difference = "Difference" }

/// Two versions of one project, compared four ways, with linked zoom.
/// Click panel A or B to make it active, then pick its version in the filmstrip.
struct CompareView: View {
    @Environment(\.palette) private var palette
    let project: ProjectGroup
    let client: Client?
    @ViewState var leftID: String
    @ViewState var rightID: String
    let done: () -> Void

    @ViewState private var mode: CompareMode = .side
    @ViewState private var active: Side = .right
    @ViewState private var split: CGFloat = 0.5
    @ViewState private var opacity: Double = 0.5
    @ViewState private var leftImage: NSImage?
    @ViewState private var rightImage: NSImage?
    @ViewState private var linkZoom = true
    @ViewState private var zoomA: CGFloat = 1
    @ViewState private var zoomB: CGFloat = 1
    @ViewState private var panA: CGSize = .zero
    @ViewState private var panB: CGSize = .zero
    @ViewState private var dragStart: CGSize?
    @ViewState private var dimsA: String?
    @ViewState private var dimsB: String?

    enum Side { case left, right }

    init(project: ProjectGroup, client: Client? = nil, left: String, right: String, done: @escaping () -> Void) {
        self.project = project
        self.client = client
        self.done = done
        _leftID = ViewState(initialValue: left)
        _rightID = ViewState(initialValue: right)
    }

    private var versions: [ProjectFile] { project.versions }
    private var left: ProjectFile { project.files.first { $0.id == leftID } ?? versions.first! }
    private var right: ProjectFile { project.files.first { $0.id == rightID } ?? project.latest }
    private func number(_ f: ProjectFile) -> Int { (versions.firstIndex { $0.id == f.id } ?? 0) + 1 }

    var body: some View {
        VStack(spacing: 14) {
            header
            modeBar
            stage.frame(maxWidth: .infinity, maxHeight: .infinity)
            zoomBar
            strip
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 16)
        .background(palette.surface)
        .task(id: leftID) {
            leftImage = await ThumbnailStore.shared.image(for: left.file.url, side: 2000, modified: left.file.modified)
            dimsA = await FileMetrics.dimensions(of: left.file)
        }
        .task(id: rightID) {
            rightImage = await ThumbnailStore.shared.image(for: right.file.url, side: 2000, modified: right.file.modified)
            dimsB = await FileMetrics.dimensions(of: right.file)
        }
    }

    // MARK: Header & modes

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(palette.onSurfaceVariant)
            if let client {
                Text(client.name).font(.system(size: 15, weight: .medium)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1).truncationMode(.middle)
                Text("/").foregroundStyle(palette.outline)
            }
            Text(project.name).font(.display(22)).foregroundStyle(palette.onSurface).lineLimit(1).truncationMode(.middle)
            Spacer()
            MaterialMenu {
                MaterialMenuAction("Swap A and B") { swap(&leftID, &rightID) }
                MaterialMenuAction("Open A: \(left.file.name)") { FileActions.open(left.file) }
                MaterialMenuAction("Open B: \(right.file.name)") { FileActions.open(right.file) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(palette.onSurface)
                    .tonalSurface(Circle())
            }
            .fixedSize()
            Button(action: done) {
                Label("Done", systemImage: "checkmark")
                    .font(.system(size: 14, weight: .bold)).fixedSize()
                    .padding(.horizontal, 20).frame(height: 40)
                    .foregroundStyle(palette.onPrimary)
                    .tonalSurface(Capsule(), tint: palette.primary)
            }
            .buttonStyle(PressScale())
            .keyboardShortcut(.cancelAction)
        }
    }

    private var modeBar: some View {
        ViewThatFits(in: .horizontal) {
            modes(compact: false)
            modes(compact: true)
        }
    }

    private func modes(compact: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(CompareMode.allCases, id: \.self) { m in
                let on = m == mode
                Button { withAnimation(Motion.fast) { mode = m } } label: {
                    Label(m.rawValue, systemImage: symbol(m))
                        .labelStyle(AdaptiveLabel(iconOnly: compact))
                        .font(.system(size: 13.5, weight: on ? .bold : .medium)).fixedSize()
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(Capsule().fill(on ? palette.primary : .clear))
                        .foregroundStyle(on ? palette.onPrimary : palette.onSurfaceVariant)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .help(m.rawValue)
                .accessibilityLabel(m.rawValue)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .tonalSurface(Capsule())
    }

    private func symbol(_ m: CompareMode) -> String {
        switch m {
        case .side: return "rectangle.split.2x1"
        case .slider: return "slider.horizontal.below.rectangle"
        case .overlay: return "square.on.square"
        case .difference: return "plusminus"
        }
    }

    // MARK: Stage

    @ViewBuilder private var stage: some View {
        switch mode {
        case .side:
            HStack(spacing: 14) {
                panel(.left)
                panel(.right)
            }
        case .slider:
            framed {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        zoomed(rightImage, .right)
                        zoomed(leftImage, .left).mask(alignment: .leading) { Rectangle().frame(width: w * split) }
                        Rectangle().fill(palette.primary).frame(width: 3).offset(x: w * split - 1.5)
                        MorphShape(from: .cookie9, to: .cookie9, progress: 0).fill(palette.primary)
                            .frame(width: 42, height: 42)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 13, weight: .black)).foregroundStyle(palette.onPrimary))
                            .offset(x: w * split - 21)
                            .frame(maxHeight: .infinity)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in split = min(max(v.location.x / max(w, 1), 0), 1) })
                }
            }
        case .overlay:
            framed { ZStack { zoomed(leftImage, .left); zoomed(rightImage, .right).opacity(opacity) } }
        case .difference:
            framed {
                ZStack { zoomed(leftImage, .left); zoomed(rightImage, .right).blendMode(.difference) }
                    .compositingGroup()
                    .background(Color.black)
                    .overlay(alignment: .bottom) {
                        Text("Black means identical. Anything bright changed between A and B.")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(12)
                    }
            }
        }
    }

    /// One version in its own panel (side by side). Clicking it makes it the one the filmstrip changes.
    private func panel(_ side: Side) -> some View {
        let f = side == .left ? left : right
        return VStack(spacing: 8) {
            panelHeader(side, f)
            zoomed(side == .left ? leftImage : rightImage, side)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.surfaceContainerLow))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { withAnimation(Motion.fast) { active = side } })
    }

    private func panelHeader(_ side: Side, _ f: ProjectFile) -> some View {
        let on = active == side
        return HStack(spacing: 10) {
            Text(side == .left ? "A" : "B").font(.system(size: 13, weight: .heavy))
                .frame(width: 32, height: 32)
                .background(Circle().fill(on ? palette.primary : palette.surfaceContainerHighest))
                .foregroundStyle(on ? palette.onPrimary : palette.onSurfaceVariant)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.file.name).font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.onSurface).lineLimit(1).truncationMode(.middle)
                Text([side == .left ? dimsA : dimsB, Format.size(f.file.size), "v\(number(f))"].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            }
            Spacer(minLength: 0)
            if on {
                Text("Active").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.primary)
                    .fixedSize()
            }
            MaterialMenu { VersionMenu(file: f) } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).frame(width: 26, height: 22)
            }
            .fixedSize()
            .foregroundStyle(palette.onSurfaceVariant)
        }
        .padding(.horizontal, 6).padding(.top, 2)
    }

    private func framed<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 8) {
            HStack {
                panelHeader(.left, left)
                panelHeader(.right, right)
            }
            content().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.surfaceContainerLow))
    }

    /// An image with this side's zoom and pan (shared with the other side when Link zoom is on).
    private func zoomed(_ image: NSImage?, _ side: Side) -> some View {
        let z = zoom(side), p = pan(side)
        return ZStack {
            Rectangle().fill(palette.surfaceDim)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .scaleEffect(z).offset(p)
            } else {
                MorphingLoader(size: 36)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    guard z > 1.01 else { return }
                    if dragStart == nil { dragStart = p }
                    let s = dragStart ?? .zero
                    setPan(CGSize(width: s.width + v.translation.width, height: s.height + v.translation.height), side)
                }
                .onEnded { _ in dragStart = nil }
        )
    }

    private func zoom(_ side: Side) -> CGFloat { linkZoom || side == .left ? zoomA : zoomB }
    private func pan(_ side: Side) -> CGSize { linkZoom || side == .left ? panA : panB }
    private func setPan(_ p: CGSize, _ side: Side) { if linkZoom || side == .left { panA = p } else { panB = p } }

    // MARK: Zoom bar

    private var zoomBar: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $linkZoom) {
                Label("Link zoom", systemImage: "link").font(.system(size: 13, weight: .medium)).fixedSize()
            }
            .toggleStyle(.switch).controlSize(.small)
            .onChange(of: linkZoom) { if linkZoom { zoomB = zoomA; panB = panA } }
            Divider().frame(height: 18)
            Button { setZoom(currentZoom / 1.25) } label: { Image(systemName: "minus") }
                .buttonStyle(.plain).frame(width: 30, height: 30).help("Zoom out")
            Text("\(Int((currentZoom * 100).rounded()))%").font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 52)
            Button { setZoom(currentZoom * 1.25) } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).frame(width: 30, height: 30).help("Zoom in")
            Divider().frame(height: 18)
            Button("Fit") { setZoom(1); panA = .zero; panB = .zero }.buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14).frame(height: 30)
                .background(Capsule().fill(palette.surfaceContainerHighest))
            if mode == .overlay {
                Divider().frame(height: 18)
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(palette.onSurfaceVariant)
                Slider(value: $opacity, in: 0...1).frame(width: 120).help("How much of B shows over A")
            }
        }
        .foregroundStyle(palette.onSurface)
        .padding(.horizontal, 16).frame(height: 46)
        .tonalSurface(Capsule())
        .animation(Motion.standard, value: mode)
    }

    private var currentZoom: CGFloat { active == .left || linkZoom ? zoomA : zoomB }

    private func setZoom(_ value: CGFloat) {
        let z = min(max(value, 1), 8)
        withAnimation(Motion.fast) {
            if linkZoom { zoomA = z; zoomB = z } else if active == .left { zoomA = z } else { zoomB = z }
            if z == 1 { panA = .zero; panB = .zero }
        }
    }

    // MARK: Version strip

    private var strip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Versions").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.onSurface)
                Text("\(versions.count)").font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(Capsule().fill(palette.surfaceContainerHighest))
                Text("Click a version to show it in \(active == .left ? "A" : "B")")
                    .font(.system(size: 11.5)).foregroundStyle(palette.onSurfaceVariant)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(versions.reversed()) { v in stripCard(v) }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.surfaceContainerLow))
    }

    private func stripCard(_ v: ProjectFile) -> some View {
        let isA = v.id == leftID, isB = v.id == rightID
        let chosen = isA || isB
        return Button {
            withAnimation(Motion.standard) { if active == .left { leftID = v.id } else { rightID = v.id } }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Thumbnail(file: v.file, side: 240)
                    .frame(width: 168, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if chosen {
                            Text(isA && isB ? "A · B" : (isA ? "A" : "B")).font(.system(size: 10.5, weight: .heavy))
                                .padding(.horizontal, 6).frame(minWidth: 20).frame(height: 20).background(palette.primary, in: Capsule())
                                .foregroundStyle(palette.onPrimary).padding(6)
                        }
                    }
                HStack(spacing: 6) {
                    Text("v\(number(v))").font(.system(size: 10.5, weight: .heavy))
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Capsule().fill(chosen ? palette.primary : palette.surfaceContainerHighest))
                        .foregroundStyle(chosen ? palette.onPrimary : palette.onSurfaceVariant)
                    Text(v.file.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(palette.onSurface)
                }
                .frame(width: 168, alignment: .leading)
                Text(Format.full.string(from: v.file.modified)).font(.system(size: 10.5)).foregroundStyle(palette.onSurfaceVariant)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(chosen ? palette.surfaceContainerHigh : .clear))
        }
        .buttonStyle(PressScale())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .help(v.file.name)
    }
}
