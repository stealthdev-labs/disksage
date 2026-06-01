import SwiftUI

/// A flat, ranked list of the biggest individual files in the scan. Folder maps
/// are great for structure, but the fastest way to reclaim space is often to
/// spot one giant file — so this gives that at a glance, with Reveal and Trash.
struct LargestFilesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.largestFiles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.largestFiles) { file in
                            LargeFileRow(file: file)
                            Divider().padding(.leading, 52)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var header: some View {
        let total = state.largestFiles.reduce(0) { $0 + $1.size }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Biggest files").font(.title2.weight(.bold))
                Text("\(state.largestFiles.count) largest files · \(ByteFormat.string(total)) total")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Text("Double-click to reveal in Finder")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(18)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("No files to list").font(.title3.weight(.semibold))
            Text("Run a scan and the largest files will show up here.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct LargeFileRow: View {
    @EnvironmentObject var state: AppState
    let file: FileNode
    @State private var hover = false
    @State private var confirmTrash = false

    var body: some View {
        let verdict = state.engine.assess(file)
        HStack(spacing: 12) {
            Image(systemName: file.kind == .app ? "app.fill" : "doc.fill")
                .font(.title3).frame(width: 22)
                .foregroundStyle(file.kind.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(file.name).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    SafetyBadge(level: verdict.level, compact: true)
                }
                HStack(spacing: 6) {
                    Text(shorten(file.path))
                        .lineLimit(1).truncationMode(.middle)
                    if let m = file.modificationDate {
                        Text("· \(age(m))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if hover {
                Button { state.revealInFinder(file.url) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless).help("Reveal in Finder")

                Button(role: .destructive) { confirmTrash = true } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).tint(.red)
                .disabled(state.isCleaning)
                .help("Move to Trash")
            }

            Text(ByteFormat.string(file.size))
                .font(.body.weight(.semibold)).monospacedDigit()
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(hover ? Theme.brandWash : Color.clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { state.revealInFinder(file.url) }
        .contextMenu {
            Button("Reveal in Finder") { state.revealInFinder(file.url) }
            Button("Move to Trash", role: .destructive) { confirmTrash = true }
        }
        .confirmationDialog("Move “\(file.name)” to the Trash?",
                            isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { Task { await state.trashNode(file) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(ByteFormat.string(file.size)) · \(verdict.reason)")
        }
        .animation(.sage, value: hover)
    }

    private func shorten(_ path: String) -> String {
        path.hasPrefix(state.home) ? "~" + path.dropFirst(state.home.count) : path
    }

    private func age(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days <= 0 { return "today" }
        if days >= 365 { return "\(days / 365)y ago" }
        if days >= 30 { return "\(days / 30)mo ago" }
        if days >= 7 { return "\(days / 7)w ago" }
        return "\(days)d ago"
    }
}
