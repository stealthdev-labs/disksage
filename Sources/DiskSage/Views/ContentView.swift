import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @State private var tab: ResultTab = .explore

    enum ResultTab: String, CaseIterable, Identifiable {
        case explore = "Explore"
        case largest = "Biggest"
        case cleanup = "Clean up"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .explore: return "chart.pie.fill"
            case .largest: return "list.number"
            case .cleanup: return "sparkles"
            }
        }
    }

    var body: some View {
        Group {
            switch state.phase {
            case .welcome:  WelcomeView()
            case .scanning: ScanningView()
            case .results:  results
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { bannerView }
        .animation(.sage, value: state.phase)
        .animation(.sageSpring, value: state.banner)
        .onAppear { state.configureAutoClean(isPro: license.isPro) }
        .onChange(of: license.isPro) { _, pro in state.configureAutoClean(isPro: pro) }
        .onChange(of: state.autoCleanEnabled) { _, _ in state.configureAutoClean(isPro: license.isPro) }
    }

    private var results: some View {
        VStack(spacing: 0) {
            switch tab {
            case .explore: ExploreView()
            case .largest: LargestFilesView()
            case .cleanup: CleanupView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if state.phase == .results {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    ForEach(ResultTab.allCases) { t in
                        Label(t.rawValue, systemImage: t.systemImage).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.rescan()
                } label: { Label("Rescan", systemImage: "arrow.clockwise") }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    state.phase = .welcome
                } label: { Label("New Scan", systemImage: "house") }
            }
        }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner = state.banner {
            let warn = banner.localizedCaseInsensitiveContains("couldn't")
                || banner.localizedCaseInsensitiveContains("need")
            HStack(spacing: 9) {
                Image(systemName: warn ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(warn ? SafetyLevel.caution.color : SafetyLevel.safe.color)
                Text(banner).font(.callout.weight(.medium))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator.opacity(0.6)))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation(.sage) { state.banner = nil }
                }
            }
        }
    }
}
