import Foundation
import Combine

/// Pro license state. DiskSage is open-core: the entire app is open source, so
/// the check below is a simple *offline* stub. The $5 license buys a notarized,
/// auto-updating prebuilt binary and supports development; people building from
/// source can unlock Pro themselves (see `demoKey()`). A real store build would
/// verify keys server-side.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isPro: Bool

    private let defaultsKey = "com.disksage.proLicenseKey"

    init() {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        isPro = saved.map(LicenseManager.isValid) ?? false
    }

    @discardableResult
    func activate(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard LicenseManager.isValid(key) else { return false }
        UserDefaults.standard.set(key, forKey: defaultsKey)
        isPro = true
        return true
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        isPro = false
    }

    // MARK: Stub validation

    /// Format: `DSAGE-XXXX-XXXX-YYYY`, where the last group is a checksum of the
    /// two middle groups.
    static func isValid(_ key: String) -> Bool {
        let parts = key.split(separator: "-").map(String.init)
        guard parts.count == 4, parts[0] == "DSAGE" else { return false }
        let body = parts[1...3]
        guard body.allSatisfy({ $0.count == 4 && $0.allSatisfy { $0.isLetter || $0.isNumber } }) else { return false }
        return checksum(parts[1] + parts[2]) == parts[3]
    }

    static func checksum(_ s: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in s.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var out = ""
        var h = hash
        for _ in 0..<4 {
            out.append(alphabet[Int(h % 36)])
            h /= 36
        }
        return out
    }

    /// A valid key for people running a build from source.
    static func demoKey() -> String {
        "DSAGE-OPEN-CORE-\(checksum("OPENCORE"))"
    }
}
