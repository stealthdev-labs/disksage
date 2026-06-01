import SwiftUI

enum Theme {
    static let brandStart = Color(red: 0.36, green: 0.42, blue: 0.95)
    static let brandEnd   = Color(red: 0.20, green: 0.80, blue: 0.74)

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brandStart, brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A soft tint of the brand for hover/selection washes.
    static var brandWash: Color { brandStart.opacity(0.10) }

    static let cardCorner: CGFloat = 14
}

// MARK: - Motion

/// A small, cohesive motion vocabulary. DiskSage's character is calm and
/// trustworthy ("Sage"), so curves are smooth and bounce is kept subtle —
/// punchy enough to feel responsive, never playful or jittery.
extension Animation {
    /// Strong ease-out for entrances and feedback. Starts fast so the UI feels
    /// like it's reacting the instant the user acts.
    static let sage = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)
    /// Calm spring for elements that should feel alive (drill-in, toasts).
    static let sageSpring = Animation.spring(duration: 0.42, bounce: 0.16)
    /// Snappy, bounce-free press feedback.
    static let sagePress = Animation.spring(duration: 0.22, bounce: 0)
}

/// Press feedback that makes any control feel like it heard the click. Scales
/// down slightly while pressed; suppressed under Reduce Motion.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration, scale: scale)
    }

    private struct PressableLabel: View {
        let configuration: Configuration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
                .animation(.sagePress, value: configuration.isPressed)
                .contentShape(Rectangle())
        }
    }
}

extension View {
    /// Convenience for `.buttonStyle(PressableButtonStyle())` while keeping the
    /// label completely custom (no system chrome).
    func pressable(scale: CGFloat = 0.97) -> some View {
        buttonStyle(PressableButtonStyle(scale: scale))
    }
}

struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }
}

/// A pill-shaped safety badge used throughout the UI.
struct SafetyBadge: View {
    let level: SafetyLevel
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: level.systemImage)
            if !compact { Text(level.label) }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, compact ? 6 : 9)
        .padding(.vertical, 4)
        .foregroundStyle(level.color)
        .background(level.color.opacity(0.15), in: Capsule())
    }
}
