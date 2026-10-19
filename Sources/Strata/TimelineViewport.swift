import SwiftUI
import AppKit
import StrataCore

/// A pannable, zoomable window onto the timeline.
///
/// - Drag anywhere to move through time (with a little momentum).
/// - Mouse wheel scrolls through time; a trackpad pans in both directions.
/// - Pinch, or ⌘ / ⌥ + scroll, zooms around the pointer.
struct TimelineViewport: View {
    @Environment(\.palette) private var palette
    let project: ProjectGroup
    let layout: TimelineLayout
    let selectedID: String
    let revealed: Bool
    let focus: FocusRequest?
    let select: (ProjectFile) -> Void
    let open: (ProjectFile) -> Void

    @ViewState private var pan: CGPoint = .zero
    @ViewState private var zoom: CGFloat = 1
    @ViewState private var viewSize: CGSize = .zero
    @ViewState private var dragOrigin: CGPoint?
    @ViewState private var zoomOrigin: CGFloat?
    @ViewState private var hovering = false
    @ViewState private var pointer: CGPoint = .zero
    @ViewState private var monitor: Any?
    @ViewState private var didIntro = false

    static let minZoom: CGFloat = 0.3
    static let maxZoom: CGFloat = 1.8
    /// Room left under the content for the floating controls.
    static let controlsClearance: CGFloat = 76

    var body: some View {
        GeometryReader { geo in
            RiverTimeline(project: project, layout: layout, selectedID: selectedID, revealed: revealed,
                          select: select, open: open)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: layout.width * zoom, height: contentHeight * zoom, alignment: .topLeading)
                .offset(x: -pan.x, y: -pan.y)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .simultaneousGesture(magnifyGesture)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): pointer = p; hovering = true
                    case .ended: hovering = false
                    }
                }
                .onAppear {
                    viewSize = geo.size
                    installMonitor()
                    intro()
                }
                .onChange(of: geo.size) {
                    viewSize = geo.size
                    pan = clamped(pan, zoom: zoom)
                }
                .onDisappear { removeMonitor() }
        }
        .overlay(alignment: .bottom) { controls.padding(.bottom, 14) }
        .onChange(of: focus) {
            if let focus { center(on: focus.id) }
        }
    }

    // MARK: Geometry

    private var contentHeight: CGFloat {
        let most = project.versions.map { project.exports(of: $0).count }.max() ?? 0
        var h = TimelineLayout.lineY + TimelineLayout.dotRow / 2 + 44
        if most > 0 { h += 14 + CGFloat(min(most, 4)) * 40 + (most > 4 ? 22 : 0) }
        return h + Self.controlsClearance
    }

    /// Keeps the content on screen; short timelines sit centred.
    private func clamped(_ p: CGPoint, zoom z: CGFloat) -> CGPoint {
        let w = layout.width * z, h = contentHeight * z
        let x = w <= viewSize.width ? -(viewSize.width - w) / 2 : min(max(p.x, 0), w - viewSize.width)
        let y = h <= viewSize.height ? 0 : min(max(p.y, 0), h - viewSize.height)
        return CGPoint(x: x, y: y)
    }

    private var maxPanX: CGFloat { max(0, layout.width * zoom - viewSize.width) }

    private func setZoom(_ value: CGFloat, around point: CGPoint) {
        let z = min(max(value, Self.minZoom), Self.maxZoom)
        let content = CGPoint(x: (pan.x + point.x) / zoom, y: (pan.y + point.y) / zoom)
        zoom = z
        pan = clamped(CGPoint(x: content.x * z - point.x, y: content.y * z - point.y), zoom: z)
    }

    private func center(on id: String) {
        guard let i = project.versions.firstIndex(where: { $0.id == id }) else { return }
        let target = CGPoint(x: layout.centers[i] * zoom - viewSize.width / 2, y: pan.y)
        withAnimation(Motion.gentle) { pan = clamped(target, zoom: zoom) }
    }

    /// First look: start at the beginning and glide to the latest version while the line draws.
    private func intro() {
        guard !didIntro else { return }
        didIntro = true
        pan = clamped(.zero, zoom: zoom)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let last = layout.centers.last else { return }
            let target = CGPoint(x: last * zoom - viewSize.width + TimelineLayout.cardWidth, y: 0)
            withAnimation(.easeInOut(duration: layout.drawDuration)) { pan = clamped(target, zoom: zoom) }
        }
    }

    // MARK: Input

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                if dragOrigin == nil {
                    dragOrigin = pan
                    NSCursor.closedHand.push()
                }
                guard let origin = dragOrigin else { return }
                pan = clamped(CGPoint(x: origin.x - v.translation.width, y: origin.y - v.translation.height), zoom: zoom)
            }
            .onEnded { v in
                if dragOrigin != nil { NSCursor.pop() }
                dragOrigin = nil
                // Momentum: keep gliding a bit in the direction of the throw.
                let fling = CGSize(width: (v.predictedEndTranslation.width - v.translation.width) * 0.6,
                                   height: (v.predictedEndTranslation.height - v.translation.height) * 0.6)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.92)) {
                    pan = clamped(CGPoint(x: pan.x - fling.width, y: pan.y - fling.height), zoom: zoom)
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomOrigin == nil { zoomOrigin = zoom }
                setZoom((zoomOrigin ?? zoom) * v.magnification, around: v.startLocation)
            }
            .onEnded { _ in zoomOrigin = nil }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hovering else { return event }
            handleScroll(event)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handleScroll(_ event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        let dx = event.scrollingDeltaX * (precise ? 1 : 40)
        let dy = event.scrollingDeltaY * (precise ? 1 : 40)

        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            setZoom(zoom * exp(dy * (precise ? 0.005 : 0.003)), around: pointer)
            return
        }
        let fitsVertically = contentHeight * zoom <= viewSize.height
        if precise && !fitsVertically {
            pan = clamped(CGPoint(x: pan.x - dx, y: pan.y - dy), zoom: zoom)
        } else {
            // A plain mouse wheel moves through time.
            let along = abs(dx) > abs(dy) ? dx : dy
            pan = clamped(CGPoint(x: pan.x - along, y: pan.y), zoom: zoom)
        }
    }

    // MARK: Floating controls

    private var controls: some View {
        HStack(spacing: 6) {
            if maxPanX > 1 { scrubber.padding(.horizontal, 8) }
            iconButton("minus.magnifyingglass", "Zoom out (⌘ + scroll, or pinch)") { zoomBy(1 / 1.3) }
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.onSurface)
                .frame(width: 44)
                .onTapGesture(count: 2) { zoomTo(1) }
                .help("Double-click for 100%")
            iconButton("plus.magnifyingglass", "Zoom in") { zoomBy(1.3) }
            Divider().frame(height: 20).padding(.horizontal, 2)
            iconButton("arrow.left.and.right.square", "Fit the whole history") { fit() }
            iconButton("sparkle", "Jump to the latest version") {
                if let last = project.versions.last { select(last) }
            }
        }
        .padding(.horizontal, 10).frame(height: 48)
        .liquidGlass(Capsule(), interactive: false)
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(palette.onSurfaceVariant)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .help(help)
    }

    /// Mini scrollbar: where you are in the whole history. Drag it to travel.
    private var scrubber: some View {
        let track: CGFloat = 180
        let total = layout.width * zoom
        let thumb = max(26, min(track, track * viewSize.width / max(total, 1)))
        let x = maxPanX > 0 ? (track - thumb) * min(max(pan.x / maxPanX, 0), 1) : 0
        return ZStack(alignment: .leading) {
            Capsule().fill(palette.surfaceContainerHighest).frame(width: track, height: 8)
            Capsule().fill(palette.primary).frame(width: thumb, height: 8).offset(x: x)
        }
        .frame(width: track, height: 30)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let f = (v.location.x - thumb / 2) / max(track - thumb, 1)
                    pan = clamped(CGPoint(x: f * maxPanX, y: pan.y), zoom: zoom)
                }
        )
        .help("Drag to move through the project's history")
    }

    private func zoomBy(_ factor: CGFloat) {
        let mid = CGPoint(x: viewSize.width / 2, y: viewSize.height / 3)
        withAnimation(Motion.standard) { setZoom(zoom * factor, around: mid) }
    }

    private func zoomTo(_ value: CGFloat) {
        let mid = CGPoint(x: viewSize.width / 2, y: viewSize.height / 3)
        withAnimation(Motion.standard) { setZoom(value, around: mid) }
    }

    private func fit() {
        let z = min(1, max(Self.minZoom, (viewSize.width - 40) / layout.width))
        withAnimation(Motion.standard) {
            zoom = z
            pan = clamped(.zero, zoom: z)
        }
    }
}
