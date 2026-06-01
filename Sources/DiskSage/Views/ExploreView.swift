import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("colorBySafety") private var colorBySafety = false
    @AppStorage("seenDrillHint") private var seenDrillHint = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                breadcrumbBar
                Divider()
                SunburstView()
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) { drillHint }
                Divider()
                legendBar
            }
            Divider()
            InspectorView()
                .frame(width: 330)
        }
        .onChange(of: state.focus?.id) { _, id in
            if let id, id != state.root?.id, !seenDrillHint {
                withAnimation(.sage) { seenDrillHint = true }
            }
        }
    }

    // MARK: Legend

    private var legendBar: some View {
        HStack(spacing: 14) {
            if colorBySafety {
                ForEach([SafetyLevel.safe, .caution, .keep], id: \.rawValue) { level in
                    legendChip(level.color, level.label)
                }
            } else {
                ForEach(FileKind.legendOrder, id: \.rawValue) { kind in
                    legendChip(kind.color, kind.label)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(.bar)
        .animation(.sage, value: colorBySafety)
    }

    private func legendChip(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    // MARK: Drill hint

    @ViewBuilder
    private var drillHint: some View {
        if state.focus?.id == state.root?.id, !seenDrillHint {
            Label("Click a ring to zoom in · click the center to step back", systemImage: "hand.tap")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(state.breadcrumb().enumerated()), id: \.element.id) { idx, node in
                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Button {
                            state.focus = node
                            state.hovered = nil
                        } label: {
                            Text(node.name)
                                .font(.subheadline)
                                .fontWeight(node.id == state.focus?.id ? .semibold : .regular)
                                .foregroundStyle(node.id == state.focus?.id ? Color.primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 12)
            Toggle(isOn: $colorBySafety) {
                Label("Safety colors", systemImage: "paintpalette")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Color the chart by delete-safety instead of file type")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
