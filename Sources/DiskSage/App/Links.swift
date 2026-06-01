import Foundation

/// Central place for outbound URLs.
enum Links {
    static let website = URL(string: "https://stealthdev-labs.github.io/disksage")!
    static let repo = URL(string: "https://github.com/stealthdev-labs/disksage")!
    /// Latest prebuilt download (GitHub Releases).
    static let download = URL(string: "https://github.com/stealthdev-labs/disksage/releases/latest")!
    /// Optional "support development" / donation page. DiskSage is free; this is
    /// a thank-you, not a paywall.
    static let support = URL(string: "https://stealthdev-labs.github.io/disksage/#support")!
    static let fullDiskAccessHelp = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
