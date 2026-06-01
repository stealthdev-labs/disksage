import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header.staggerIn(0, appeared: appeared, reduceMotion: reduceMotion)
                scanOptions.staggerIn(1, appeared: appeared, reduceMotion: reduceMotion)
                legend.staggerIn(2, appeared: appeared, reduceMotion: reduceMotion)
                Text("DiskSage never deletes anything on its own. Items you clean go to the Trash, so you can always put them back.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .staggerIn(3, appeared: appeared, reduceMotion: reduceMotion)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .onAppear { appeared = true }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 84, height: 84)
                    .shadow(color: Theme.brandStart.opacity(0.4), radius: 16, y: 6)
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("DiskSage")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("See where your space went — and clean it up safely.\nDiskSage tells you what's junk, what to review, and what to never touch.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if state.volumeTotalBytes > 0 {
                Text("\(ByteFormat.string(state.volumeFreeBytes)) free of \(ByteFormat.string(state.volumeTotalBytes))")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.background.secondary, in: Capsule())
            }
        }
        .padding(.top, 12)
    }

    private var scanOptions: some View {
        HStack(spacing: 16) {
            ScanCard(icon: "house.fill", title: "Scan Home",
                     subtitle: "Recommended — where reclaimable space usually hides.",
                     prominent: true) { state.scanHome() }
            ScanCard(icon: "folder.fill", title: "Choose Folder…",
                     subtitle: "Point DiskSage at any folder or external drive.") { state.chooseFolder() }
            ScanCard(icon: "internaldrive.fill", title: "Whole Mac",
                     subtitle: "Everything. Needs Full Disk Access for system areas.") { state.scanWholeMac() }
        }
        .frame(maxWidth: 760)
    }

    private var legend: some View {
        HStack(spacing: 22) {
            ForEach([SafetyLevel.safe, .caution, .keep], id: \.rawValue) { level in
                HStack(spacing: 7) {
                    Image(systemName: level.systemImage).foregroundStyle(level.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(level.label).font(.subheadline.weight(.semibold))
                        Text(level.shortNote).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 760)
        .card()
    }
}

private struct ScanCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(prominent ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.secondary))
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(.background.secondary)
                    .overlay {
                        if hovering {
                            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                                .fill(Theme.brandWash)
                        }
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(prominent ? AnyShapeStyle(Theme.brandGradient)
                                            : AnyShapeStyle(Color(nsColor: .separatorColor).opacity(hovering ? 0.9 : 0.4)),
                                  lineWidth: prominent ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.14 : 0.05),
                    radius: hovering ? 16 : 6, y: hovering ? 7 : 2)
            .scaleEffect(hovering ? 1.025 : 1)
        }
        .pressable()
        .onHover { hovering = $0 }
        .animation(.sage, value: hovering)
    }
}

/// Fade-and-rise entrance with a per-element delay. Movement is dropped under
/// Reduce Motion (the fade stays, which aids comprehension without motion).
private struct StaggerIn: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: (appeared || reduceMotion) ? 0 : 12)
            .animation(.sage.delay(Double(index) * 0.07), value: appeared)
    }
}

private extension View {
    func staggerIn(_ index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        modifier(StaggerIn(index: index, appeared: appeared, reduceMotion: reduceMotion))
    }
}
