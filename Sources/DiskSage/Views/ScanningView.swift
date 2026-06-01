import SwiftUI

struct ScanningView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 6)
                    .frame(width: 96, height: 96)
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) { spin = true }
            }
            VStack(spacing: 6) {
                Text("Scanning \(state.scanTargetName)…")
                    .font(.title2.weight(.semibold))
                Text("\(state.progress.filesScanned.formatted()) files · \(ByteFormat.string(state.progress.bytesScanned))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.sage, value: state.progress.filesScanned)
            }
            Text(displayPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)

            Button("Cancel", role: .cancel) { state.cancelScan() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var displayPath: String {
        let p = state.progress.currentPath
        return p.hasPrefix(state.home) ? "~" + p.dropFirst(state.home.count) : p
    }
}
