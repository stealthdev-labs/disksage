import SwiftUI

struct SunburstSegment: Identifiable {
    let id: UUID
    let node: FileNode
    let ring: Int
    let start: Double   // radians, 0 at top, increasing clockwise
    let end: Double
}

struct SunburstView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("colorBySafety") private var colorBySafety = false

    private let maxRings = 4
    private let minAngle = 0.012
    private let holeRatio: CGFloat = 0.32
    private let outerScale: CGFloat = 0.98

    @State private var segments: [SunburstSegment] = []

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, sz in draw(into: ctx, size: sz) }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): state.hovered = hitTest(pt, size: size)?.node
                        case .ended: state.hovered = nil
                        }
                    }
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            if let seg = hitTest(value.location, size: size) {
                                state.focusOn(seg.node)
                            }
                        }
                    )
                CenterHole(diameter: holeDiameter(for: size))
            }
            .frame(width: size.width, height: size.height)
        }
        .onAppear(perform: recompute)
        .onChange(of: layoutKey) { _, _ in recompute() }
    }

    private var layoutKey: String { "\(state.focus?.id.uuidString ?? "")-\(state.revision)" }

    private func recompute() {
        guard let focus = state.focus else { segments = []; return }
        segments = Self.layout(focus: focus, maxRings: maxRings, minAngle: minAngle)
    }

    // MARK: Drawing

    private func draw(into ctx: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 * outerScale
        let hole = radius * holeRatio
        let thickness = (radius - hole) / CGFloat(maxRings)
        let hoveredID = state.hovered?.id
        let engine = state.engine

        for seg in segments {
            let inner = hole + thickness * CGFloat(seg.ring)
            let outer = inner + thickness - 1.5
            let gap = min(0.006, (seg.end - seg.start) * 0.18)
            let path = ringSegment(center: center, inner: inner, outer: outer,
                                   start: seg.start + gap, end: seg.end - gap)

            let base = colorBySafety ? engine.assess(seg.node).level.color : seg.node.kind.color
            let isHovered = seg.node.id == hoveredID
            let dim = 1.0 - Double(seg.ring) * 0.09
            ctx.fill(path, with: .color(isHovered ? base : base.opacity(dim)))
            if isHovered {
                ctx.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 2)
            }
        }
    }

    private func ringSegment(center: CGPoint, inner: CGFloat, outer: CGFloat,
                             start: Double, end: Double) -> Path {
        var path = Path()
        guard end > start else { return path }
        let steps = max(2, Int((end - start) / 0.05))
        func point(_ r: CGFloat, _ a: Double) -> CGPoint {
            CGPoint(x: center.x + r * CGFloat(sin(a)), y: center.y - r * CGFloat(cos(a)))
        }
        path.move(to: point(inner, start))
        path.addLine(to: point(outer, start))
        for i in 0...steps { path.addLine(to: point(outer, start + (end - start) * Double(i) / Double(steps))) }
        path.addLine(to: point(inner, end))
        for i in 0...steps { path.addLine(to: point(inner, end - (end - start) * Double(i) / Double(steps))) }
        path.closeSubpath()
        return path
    }

    // MARK: Center

    private func holeDiameter(for size: CGSize) -> CGFloat {
        let radius = min(size.width, size.height) / 2 * outerScale
        return radius * holeRatio * 1.7
    }

    // MARK: Hit testing

    private func hitTest(_ point: CGPoint, size: CGSize) -> SunburstSegment? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 * outerScale
        let hole = radius * holeRatio
        let thickness = (radius - hole) / CGFloat(maxRings)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let r = hypot(dx, dy)
        guard r >= hole, r <= radius else { return nil }
        let ring = Int((r - hole) / thickness)
        var angle = atan2(Double(dx), Double(-dy))
        if angle < 0 { angle += 2 * .pi }
        return segments.first { $0.ring == ring && angle >= $0.start && angle < $0.end }
    }

    // MARK: Layout

    static func layout(focus: FileNode, maxRings: Int, minAngle: Double) -> [SunburstSegment] {
        var segs: [SunburstSegment] = []
        func place(_ node: FileNode, _ ring: Int, _ start: Double, _ end: Double) {
            guard ring < maxRings else { return }
            let total = Double(max(node.size, 1))
            var cursor = start
            for child in node.sortedChildren() {
                let span = (end - start) * Double(child.size) / total
                if span < minAngle { cursor += span; continue }
                segs.append(SunburstSegment(id: child.id, node: child, ring: ring,
                                            start: cursor, end: cursor + span))
                if child.isDirectory && !child.children.isEmpty {
                    place(child, ring + 1, cursor, cursor + span)
                }
                cursor += span
            }
        }
        place(focus, 0, 0, 2 * .pi)
        return segs
    }
}

/// The hub at the center of the sunburst: shows the focused folder's name and
/// size, and — when drilled in — acts as one big "step back" target.
private struct CenterHole: View {
    @EnvironmentObject var state: AppState
    let diameter: CGFloat
    @State private var hover = false

    var body: some View {
        let isRoot = state.focus?.id == state.root?.id
        let active = hover && !isRoot
        VStack(spacing: 3) {
            if !isRoot {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.brandStart)
                    .opacity(active ? 1 : 0.65)
            }
            Text(state.focus?.name ?? "")
                .font(.headline).lineLimit(1).truncationMode(.middle)
            Text(ByteFormat.string(state.focus?.size ?? 0))
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            if let count = state.focus?.fileCount {
                Text("\(count.formatted()) files").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(Circle().strokeBorder(active ? AnyShapeStyle(Theme.brandStart.opacity(0.6))
                                              : AnyShapeStyle(Color(nsColor: .separatorColor).opacity(0.5))))
        .scaleEffect(active ? 1.04 : 1)
        .contentShape(Circle())
        .onTapGesture { if !isRoot { state.goUp() } }
        .onHover { hover = $0 }
        .help(isRoot ? "" : "Back to parent folder")
        .animation(.sage, value: active)
    }
}
