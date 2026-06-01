import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AutoCleanSettings()
                .tabItem { Label("Auto-clean", systemImage: "calendar.badge.clock") }
            LicenseSettings()
                .tabItem { Label("License", systemImage: "key.fill") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

private struct GeneralSettings: View {
    @AppStorage("oldDownloadDays") private var oldDownloadDays = 30
    @AppStorage("staleFileMonths") private var staleFileMonths = 12
    @AppStorage("colorBySafety") private var colorBySafety = false

    var body: some View {
        Form {
            Section("Suggestions") {
                Stepper(value: $oldDownloadDays, in: 7...365, step: 7) {
                    Text("Flag downloads untouched for **\(oldDownloadDays)** days")
                }
                Stepper(value: $staleFileMonths, in: 0...60) {
                    Text(staleFileMonths == 0
                         ? "Don't flag old, large personal files"
                         : "Flag large files untouched for **\(staleFileMonths)** months")
                }
                Text("Large files (200 MB+) in Desktop, Documents, Movies, Music and Pictures that you haven't changed in this long are flagged for review. Affects the next scan.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Chart") {
                Toggle("Color the sunburst by delete-safety", isOn: $colorBySafety)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AutoCleanSettings: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager

    private let categories: [CleanupCategory] = CleanupCategory.allCases.filter { $0.autoCleanEligible }

    var body: some View {
        Form {
            if !license.isPro {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text("Auto-clean is a Pro feature").font(.headline)
                            Text("Unlock scheduled, hands-off cleanup of safe junk.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Scheduled cleanup") {
                Toggle("Automatically clean safe junk", isOn: $state.autoCleanEnabled)
                    .disabled(!license.isPro)
                Text("Runs on launch and every 6 hours while DiskSage is open. Only items rated **Safe** are touched, and everything goes to the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("What gets swept") {
                ForEach(categories) { cat in
                    Label(cat.title, systemImage: cat.systemImage)
                        .foregroundStyle(license.isPro ? .primary : .secondary)
                }
            }

            Section {
                HStack {
                    Button("Run now") { Task { await state.runAutoCleanSweep() } }
                        .disabled(!license.isPro || state.autoRunning)
                    if state.autoRunning { ProgressView().controlSize(.small) }
                    Spacer()
                    if let last = state.autoLastRun {
                        Text("Last: \(last.formatted(date: .omitted, time: .shortened)) · freed \(ByteFormat.string(state.autoLastFreed ?? 0))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct LicenseSettings: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: license.isPro ? "checkmark.seal.fill" : "person.fill")
                        .foregroundStyle(license.isPro ? SafetyLevel.safe.color : .secondary)
                    Text(license.isPro ? "DiskSage Pro — active" : "DiskSage Free")
                        .font(.headline)
                    Spacer()
                    if license.isPro {
                        Button("Deactivate") { license.deactivate() }
                    }
                }
            }

            if !license.isPro {
                Section("Activate") {
                    TextField("DSAGE-XXXX-XXXX-XXXX", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(activate)
                    if failed {
                        Label("That key isn't valid.", systemImage: "xmark.octagon")
                            .font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        Button("Activate", action: activate).disabled(key.isEmpty)
                        Button("Support development") { openURL(Links.support) }
                        Spacer()
                        Button("Use source-build key") { key = LicenseManager.demoKey() }
                            .help("DiskSage is free and open source — this unlocks Pro instantly.")
                    }
                }
            }

            Section {
                Text("DiskSage is free and open source — every feature, including auto-clean. Use the source-build key above to unlock Pro instantly. Donations are optional and simply fund development.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func activate() {
        failed = !license.activate(key)
        if !failed { key = "" }
    }
}

private struct AboutSettings: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 64, height: 64)
                Image(systemName: "chart.pie.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            }
            Text("DiskSage").font(.title.weight(.bold))
            Text("Version \(AppInfo.version)").font(.callout).foregroundStyle(.secondary)
            Text("The open-source disk cleaner that knows what's safe to delete.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Website") { openURL(Links.website) }
                Button("Source on GitHub") { openURL(Links.repo) }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

enum AppInfo {
    static let version = "1.0.0"
}
