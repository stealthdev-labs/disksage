import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @State private var showUpsell = false

    private var safe: [Suggestion] { state.suggestions.filter { $0.safety == .safe } }
    private var review: [Suggestion] { state.suggestions.filter { $0.safety != .safe } }

    var body: some View {
        VStack(spacing: 0) {
            summary
            Divider()
            if state.suggestions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if !safe.isEmpty {
                            Section { rows(safe) } header: { sectionHeader("Safe to delete", safe) }
                        }
                        if !review.isEmpty {
                            Section { rows(review) } header: { sectionHeader("Review first", review) }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showUpsell) { ProUpsell() }
    }

    // MARK: Summary header

    private var summary: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reclaim up to \(ByteFormat.string(state.totalReclaim))")
                    .font(.title2.weight(.bold))
                Text("\(state.suggestions.count) suggestions · \(ByteFormat.string(state.selectedReclaim)) selected")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Text("Items are moved to the Trash — nothing is deleted permanently.")
                    .font(.caption).foregroundStyle(.tertiary)
                if state.findingDuplicates {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Checking for duplicate files…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Select safe") { state.setAll(selected: true, safeOnly: true) }
                    Button("Select none") { state.setAll(selected: false, safeOnly: false) }
                }
                .controlSize(.small)

                HStack(spacing: 8) {
                    Button {
                        if license.isPro { autoCleanSafe() } else { showUpsell = true }
                    } label: {
                        Label(license.isPro ? "Auto-clean safe" : "Auto-clean (Pro)",
                              systemImage: license.isPro ? "sparkles" : "lock.fill")
                    }
                    .controlSize(.large)

                    Button {
                        Task { await state.cleanSelected() }
                    } label: {
                        if state.isCleaning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Clean Selected", systemImage: "trash")
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(state.selectedReclaim == 0 || state.isCleaning)
                }
            }
        }
        .padding(18)
    }

    private func sectionHeader(_ title: String, _ items: [Suggestion]) -> some View {
        HStack {
            Text(title).font(.headline)
            Text("\(items.count) · \(ByteFormat.string(items.reduce(0) { $0 + $1.size }))")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(.bar)
    }

    private func rows(_ items: [Suggestion]) -> some View {
        ForEach(items) { item in
            SuggestionRow(suggestion: item) { state.toggle(item) }
            Divider().padding(.leading, 52)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52)).foregroundStyle(SafetyLevel.safe.color)
            Text("Nothing obvious to clean").font(.title3.weight(.semibold))
            Text("DiskSage didn't find reclaimable junk in this scan. Try scanning your whole Mac, or explore the chart for large personal files.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func autoCleanSafe() {
        state.setAll(selected: true, safeOnly: true)
        Task { await state.cleanSelected() }
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(suggestion.selected ? AnyShapeStyle(Theme.brandStart) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))

            Image(systemName: suggestion.category.systemImage)
                .font(.title3).frame(width: 22)
                .foregroundStyle(suggestion.safety.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(suggestion.title).font(.body.weight(.medium)).lineLimit(1)
                    SafetyBadge(level: suggestion.safety, compact: true)
                }
                Text(suggestion.reason)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !suggestion.detail.isEmpty {
                    Text(suggestion.detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(ByteFormat.string(suggestion.size))
                .font(.body.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background {
            if suggestion.selected { Theme.brandStart.opacity(0.07) }
            else if hover { Theme.brandWash }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hover = $0 }
        .animation(.sage, value: hover)
        .animation(.sage, value: suggestion.selected)
    }
}
