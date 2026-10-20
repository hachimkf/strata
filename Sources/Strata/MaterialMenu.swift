import SwiftUI
import AppKit

/// Menus stay in the hosting window instead of opening an AppKit menu over other apps.
@MainActor
final class MaterialMenus: ObservableObject {
    struct Request: Identifiable {
        let id = UUID()
        let anchor: NSView
        let point: CGPoint?
        let palette: Palette
        let content: AnyView
    }

    @Published var request: Request?
    private var escapeMonitor: Any?
    private weak var previousResponder: NSResponder?

    func show(anchor: NSView, point: CGPoint? = nil, palette: Palette, content: AnyView) {
        dismiss()
        previousResponder = anchor.window?.firstResponder
        request = Request(anchor: anchor, point: point, palette: palette, content: content)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, event.window == self?.request?.anchor.window else { return event }
            self?.dismiss()
            return nil
        }
    }

    func dismiss() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        let window = request?.anchor.window
        request = nil
        if let previousResponder { window?.makeFirstResponder(previousResponder) }
        previousResponder = nil
    }
}

private struct MaterialMenusKey: EnvironmentKey { static let defaultValue: MaterialMenus? = nil }
private struct InsideMaterialMenuKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var materialMenus: MaterialMenus? {
        get { self[MaterialMenusKey.self] }
        set { self[MaterialMenusKey.self] = newValue }
    }
    var insideMaterialMenu: Bool {
        get { self[InsideMaterialMenuKey.self] }
        set { self[InsideMaterialMenuKey.self] = newValue }
    }
}

enum MaterialMenuLayout {
    static func origin(anchor: CGRect, panel: CGSize, window: CGSize) -> CGPoint {
        let inset: CGFloat = 12
        let x = min(max(anchor.minX, inset), max(inset, window.width - panel.width - inset))
        let below = anchor.maxY + 6
        let y = below + panel.height <= window.height - inset ? below : anchor.minY - panel.height - 6
        return CGPoint(x: x, y: min(max(y, inset), max(inset, window.height - panel.height - inset)))
    }
}

private struct MaterialMenuHost: ViewModifier {
    @StateObject private var menus = MaterialMenus()
    @ViewState private var root: NSView?

    func body(content: Content) -> some View {
        content
            .background(MenuAnchorReference(view: $root))
            .environment(\.materialMenus, menus)
            .overlay {
                if let request = menus.request, let root {
                    GeometryReader { geometry in
                        let rect = request.point.map { CGRect(origin: $0, size: .zero) } ?? request.anchor.bounds
                        MaterialMenuOverlay(menus: menus, request: request,
                                            anchor: root.convert(rect, from: request.anchor), window: geometry.size)
                            .environment(\.palette, request.palette)
                            .environment(\.materialMenus, menus)
                            .id(request.id)
                    }
                }
            }
            .onDisappear { menus.dismiss() }
    }
}

private struct MaterialMenuOverlay: View {
    @ObservedObject var menus: MaterialMenus
    let request: MaterialMenus.Request
    let anchor: CGRect
    let window: CGSize
    @ViewState private var contentHeight: CGFloat = 300

    var body: some View {
        let size = CGSize(width: min(340, max(0, window.width - 24)),
                          height: min(contentHeight, max(0, window.height - 24)))
        let origin = MaterialMenuLayout.origin(anchor: anchor, panel: size, window: window)
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { menus.dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) { request.content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(GeometryReader { geo in
                        Color.clear.onChange(of: geo.size.height, initial: true) {
                            if geo.size.height > 0 { contentHeight = geo.size.height }
                        }
                    })
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(width: size.width, height: size.height)
            .background(request.palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .environment(\.insideMaterialMenu, true)
            .accessibilityLabel("Actions")
            .offset(x: origin.x, y: origin.y)
        }
    }
}

struct MaterialMenu<Label: View, Items: View>: View {
    @Environment(\.materialMenus) private var menus
    @Environment(\.insideMaterialMenu) private var nested
    @Environment(\.palette) private var palette
    @ViewState private var anchor: NSView?
    @ViewState private var expanded = false
    @ViewBuilder var content: () -> Items
    @ViewBuilder var label: () -> Label

    var body: some View {
        if nested {
            VStack(alignment: .leading, spacing: 2) {
                Button { withAnimation(Motion.fast) { expanded.toggle() } } label: {
                    HStack {
                        label()
                        Spacer()
                        Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .buttonStyle(MaterialMenuRowStyle())
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                if expanded { VStack(alignment: .leading, spacing: 2) { content() }.padding(.leading, 12) }
            }
        } else {
            Button {
                if let anchor { menus?.show(anchor: anchor, palette: palette, content: AnyView(content())) }
            } label: { label() }
                .buttonStyle(PressScale())
                .background(MenuAnchorReference(view: $anchor))
                .accessibilityAddTraits(.isButton)
        }
    }
}

extension MaterialMenu where Label == Text {
    init(_ title: String, @ViewBuilder content: @escaping () -> Items) {
        self.content = content
        self.label = { Text(title) }
    }
}

/// Native button behavior with explicit dismissal, for pointer, keyboard and accessibility actions.
struct MaterialMenuAction<Label: View>: View {
    @Environment(\.materialMenus) private var menus
    let role: ButtonRole?
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(role: ButtonRole? = nil, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.role = role
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(role: role) {
            menus?.dismiss()
            action()
        } label: { label() }
        .buttonStyle(MaterialMenuRowStyle())
    }
}

extension MaterialMenuAction where Label == Text {
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action, label: { Text(title) })
    }
}

private struct MaterialMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(MaterialMenuRow(role: configuration.role, pressed: configuration.isPressed))
    }
}

private struct MaterialMenuRow: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var enabled
    var role: ButtonRole?
    var pressed = false
    @ViewState private var hovering = false
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(role == .destructive ? Color.red : palette.onSurface)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(hovering || pressed ? palette.secondaryContainer : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .animation(Motion.effects, value: hovering)
    }
}

private struct MaterialContextMenu<Items: View>: ViewModifier {
    @Environment(\.materialMenus) private var menus
    @Environment(\.palette) private var palette
    @ViewState private var anchor: NSView?
    @ViewBuilder var items: () -> Items
    func body(content: Content) -> some View {
        content.background(MenuAnchorReference(view: $anchor, contextClick: { point in
            guard let anchor, menus?.request == nil else { return false }
            menus?.show(anchor: anchor, point: point, palette: palette, content: AnyView(items()))
            return menus != nil
        }))
    }
}

private struct MenuAnchorReference: NSViewRepresentable {
    @Binding var view: NSView?
    var contextClick: ((CGPoint) -> Bool)? = nil
    func makeNSView(context: Context) -> AnchorView {
        let result = AnchorView()
        DispatchQueue.main.async { view = result }
        return result
    }
    func updateNSView(_ nsView: AnchorView, context: Context) { nsView.contextClick = contextClick }

    final class AnchorView: NSView {
        var contextClick: ((CGPoint) -> Bool)? {
            didSet {
                guard contextClick != nil, monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                    guard let self, self.window != nil, self.window == event.window,
                          !self.isHiddenOrHasHiddenAncestor else { return event }
                    let point = self.convert(event.locationInWindow, from: nil)
                    guard self.visibleRect.contains(point), self.contextClick?(point) == true else { return event }
                    return nil
                }
            }
        }
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

extension View {
    func materialMenuHost() -> some View { modifier(MaterialMenuHost()) }
    func materialContextMenu<Items: View>(@ViewBuilder items: @escaping () -> Items) -> some View {
        modifier(MaterialContextMenu(items: items))
    }
}
