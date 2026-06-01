import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmTrash = false

    private var node: FileNode? { state.hovered ?? state.focus }

    var body: some View {
        ScrollView {
            if let node {
                let verdict = state.engine.assess(node)
                VStack(alignment: .leading, spacing: 16) {
                    header(node)
                    sizeBlock(node)
                    verdictBlock(node, verdict)
                    metaBlock(node)
                    actions(node, verdict)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("Hover the chart to inspect a folder")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .padding(.horizontal)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(_ node: FileNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.title2)
                .foregroundStyle(node.kind.color)
            Text(node.name)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func sizeBlock(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ByteFormat.string(node.size))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            if node.parent != nil {
                Text("\(Int((node.fractionOfParent * 100).rounded()))% of \(node.parent?.name ?? "parent")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func verdictBlock(_ node: FileNode, _ verdict: SafetyAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SafetyBadge(level: verdict.level)
            Text(verdict.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let cat = verdict.category {
                Label(cat.title, systemImage: cat.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(verdict.level.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(verdict.level.color.opacity(0.3)))
    }

    private func metaBlock(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Path", value: shorten(node.path))
            if node.isDirectory { row("Contains", value: "\(node.fileCount.formatted()) files") }
            if let m = node.modificationDate {
                row("Modified", value: "\(m.formatted(date: .abbreviated, time: .omitted)) · \(age(m))")
            }
            if node.isPartial {
                Label("Some items couldn't be read (permissions).", systemImage: "lock.slash")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.tertiary).frame(width: 64, alignment: .leading)
            Text(value).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(3).truncationMode(.middle)
        }
    }

    private func actions(_ node: FileNode, _ verdict: SafetyAssessment) -> some View {
        VStack(spacing: 8) {
            Button {
                state.revealInFinder(node.url)
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
            }

            if node.isDirectory && !node.children.isEmpty {
                Button {
                    state.focusOn(node)
                } label: {
                    Label("Focus on This", systemImage: "scope").frame(maxWidth: .infinity)
                }
            }

            if verdict.level != .keep {
                Button(role: .destructive) {
                    if verdict.level == .safe { trash(node) } else { confirmTrash = true }
                } label: {
                    Label("Move to Trash", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .tint(.red)
                .disabled(state.isCleaning)
                .confirmationDialog("Move “\(node.name)” to the Trash?",
                                    isPresented: $confirmTrash, titleVisibility: .visible) {
                    Button("Move to Trash", role: .destructive) { trash(node) }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(verdict.reason)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func trash(_ node: FileNode) {
        Task { await state.trashNode(node) }
    }

    private func shorten(_ path: String) -> String {
        path.hasPrefix(state.home) ? "~" + path.dropFirst(state.home.count) : path
    }

    /// Human "how long ago" for the modified date — makes staleness obvious.
    private func age(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days <= 0 { return "today" }
        if days >= 365 { return "\(days / 365)y ago" }
        if days >= 30 { return "\(days / 30)mo ago" }
        if days >= 7 { return "\(days / 7)w ago" }
        return "\(days)d ago"
    }
}
