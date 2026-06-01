import SwiftUI

struct ProUpsell: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 64, height: 64)
                Image(systemName: "sparkles").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            }
            VStack(spacing: 4) {
                Text("DiskSage Pro").font(.title2.weight(.bold))
                Text("Free & open source — unlock it yourself, support if it helped.").foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                feature("calendar.badge.clock", "Scheduled auto-clean",
                        "DiskSage sweeps regenerable junk on a schedule, hands-off.")
                feature("checkmark.shield.fill", "Safe categories only",
                        "Auto-clean only ever touches items rated Safe — never your data.")
                feature("heart.fill", "Support development",
                        "DiskSage is open source. Buying Pro funds the work and gets you a notarized, auto-updating build.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                SettingsLink {
                    Text("Enter License…")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    openURL(Links.support)
                } label: {
                    Text("Support development").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button("Maybe later") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 420)
    }

    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.brandStart).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
