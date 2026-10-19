import SwiftUI
import AppKit
import StrataCore

enum CompareMode: String, CaseIterable { case side = "Side by side", slider = "Slider", overlay = "Overlay", difference = "Difference" }

/// Two versions of one project, compared four ways. Pick versions from the strip at the bottom.
struct CompareView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let project: ProjectGroup
    @ViewState var leftID: String
    @ViewState var rightID: String

    @ViewState private var mode: CompareMode = .slider
    @ViewState private var split: CGFloat = 0.5
    @ViewState private var opacity: Double = 0.5
    @ViewState private var leftImage: NSImage?
    @ViewState private var rightImage: NSImage?
    @ViewState private var picking: Side = .right

    enum Side { case left, right }

    init(project: ProjectGroup, left: String, right: String) {
        self.project = project
        _leftID = ViewState(initialValue: left)
        _rightID = ViewState(initialValue: right)
    }

    private var versions: [ProjectFile] { project.versions }
    private var left: ProjectFile { project.files.first { $0.id == leftID } ?? versions.first! }
    private var right: ProjectFile { project.files.first { $0.id == rightID } ?? project.latest }

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding(.horizontal, 22).padding(.vertical, 14)
            stage
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            strip.padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(palette.surfaceDim)
        .task(id: leftID) { leftImage = await image(left) }
        .task(id: rightID) { rightImage = await image(right) }
    }

    private func image(_ f: ProjectFile) async -> NSImage? {
        await ThumbnailStore.shared.image(for: f.file.url, side: 1800, modified: f.file.modified)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("COMPARE").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundStyle(palette.tertiary)
                Text(project.name).font(.display(24)).foregroundStyle(palette.onSurface)
            }
            Spacer()
            ButtonGroup(items: CompareMode.allCases.map { ($0, $0.rawValue, symbol($0)) }, selection: $mode, height: 38)
            if mode == .overlay {
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(palette.onSurfaceVariant)
                    Slider(value: $opacity, in: 0...1).frame(width: 140)
                }
                .transition(.scale.combined(with: .opacity))
            }
            Button { swap(&leftID, &rightID) } label: {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38).background(palette.secondaryContainer, in: Circle())
                    .foregroundStyle(palette.onSecondaryContainer)
            }
            .buttonStyle(PressScale()).help("Swap sides")
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .animation(Motion.standard, value: mode)
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
                panel(leftImage, left, tag: "A")
                panel(rightImage, right, tag: "B")
            }
        case .slider:
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .leading) {
                    picture(rightImage)
                    picture(leftImage)
                        .mask(alignment: .leading) { Rectangle().frame(width: size.width * split) }
                    // Handle
                    Rectangle().fill(palette.primary).frame(width: 3)
                        .offset(x: size.width * split - 1.5)
                    MorphShape(from: .cookie9, to: .cookie9, progress: 0)
                        .fill(palette.primary)
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 14, weight: .black)).foregroundStyle(palette.onPrimary))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                        .offset(x: size.width * split - 22, y: 0)
                        .frame(maxHeight: .infinity)
                }
                .overlay(alignment: .topLeading) { label(left, "A").padding(12) }
                .overlay(alignment: .topTrailing) { label(right, "B").padding(12) }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    split = min(max(v.location.x / max(size.width, 1), 0), 1)
                })
            }
        case .overlay:
            ZStack {
                picture(leftImage)
                picture(rightImage).opacity(opacity)
            }
            .overlay(alignment: .topLeading) { label(left, "A").padding(12) }
            .overlay(alignment: .topTrailing) { label(right, "B").padding(12) }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .difference:
            ZStack {
                picture(leftImage)
                picture(rightImage).blendMode(.difference)
            }
            .compositingGroup()
            .background(Color.black)
            .overlay(alignment: .bottom) {
                Text("Black means identical. Anything bright changed between A and B.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func picture(_ image: NSImage?) -> some View {
        ZStack {
            Rectangle().fill(palette.surfaceContainerHighest)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                MorphingLoader(size: 40)
            }
        }
    }

    private func panel(_ image: NSImage?, _ f: ProjectFile, tag: String) -> some View {
        picture(image)
            .overlay(alignment: .topLeading) { label(f, tag).padding(12) }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func label(_ f: ProjectFile, _ tag: String) -> some View {
        HStack(spacing: 8) {
            Text(tag).font(.system(size: 12, weight: .black))
                .frame(width: 24, height: 24)
                .background(palette.primary, in: Circle()).foregroundStyle(palette.onPrimary)
            VStack(alignment: .leading, spacing: 0) {
                Text(f.file.name).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text(Format.full.string(from: f.file.modified)).font(.system(size: 10.5, weight: .medium)).opacity(0.75)
            }
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    // MARK: Version strip

    private var strip: some View {
        HStack(spacing: 14) {
            ButtonGroup(items: [(Side.left, "Pick A", "a.circle.fill"), (Side.right, "Pick B", "b.circle.fill")],
                        selection: $picking, height: 34)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(versions) { v in
                        let isA = v.id == leftID, isB = v.id == rightID
                        Button {
                            withAnimation(Motion.standard) { if picking == .left { leftID = v.id } else { rightID = v.id } }
                        } label: {
                            VStack(spacing: 4) {
                                Thumbnail(file: v.file, side: 160)
                                    .frame(width: 84, height: 63)
                                    .clipShape(RoundedRectangle(cornerRadius: isA || isB ? 16 : 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: isA || isB ? 16 : 10, style: .continuous)
                                        .stroke(isA || isB ? palette.primary : .clear, lineWidth: 3))
                                    .overlay(alignment: .topLeading) {
                                        if isA || isB {
                                            Text(isA ? "A" : "B").font(.system(size: 10, weight: .black))
                                                .frame(width: 18, height: 18).background(palette.primary, in: Circle())
                                                .foregroundStyle(palette.onPrimary).padding(4)
                                        }
                                    }
                                Text(Format.date(v.file.modified)).font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                        .buttonStyle(PressScale())
                        .help(v.file.name)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
