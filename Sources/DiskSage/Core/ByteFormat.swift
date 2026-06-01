import Foundation

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func string(_ bytes: Int64) -> String {
        if bytes <= 0 { return "Zero KB" }
        return formatter.string(fromByteCount: bytes)
    }

    static func string(_ bytes: Int) -> String { string(Int64(bytes)) }
}
