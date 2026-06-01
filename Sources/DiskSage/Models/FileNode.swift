import Foundation

/// A node in the scanned filesystem tree. Reference type so children can point
/// back at parents and aggregated sizes can be filled in bottom-up.
final class FileNode: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    let kind: FileKind
    let modificationDate: Date?

    /// Aggregated allocated size in bytes (this node + everything beneath it).
    var size: Int64
    /// Number of regular files at or beneath this node.
    var fileCount: Int
    /// True when the subtree was not fully read (e.g. permission denied).
    var isPartial: Bool = false

    weak var parent: FileNode?
    var children: [FileNode] = []

    /// Advisory verdict, filled in by `SafetyEngine`.
    var assessment: SafetyAssessment?

    init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isSymlink: Bool,
        size: Int64,
        fileCount: Int,
        modificationDate: Date?
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
        self.fileCount = fileCount
        self.modificationDate = modificationDate
        self.kind = FileKind.infer(name: name, isDirectory: isDirectory)
    }

    var path: String { url.path }

    /// Depth from the scan root (root == 0).
    var depth: Int {
        var d = 0
        var p = parent
        while p != nil { d += 1; p = p?.parent }
        return d
    }

    /// Children sorted largest-first — the order the sunburst draws them in.
    func sortedChildren() -> [FileNode] {
        children.sorted { $0.size > $1.size }
    }

    /// Fraction of the parent's size this node occupies (0...1).
    var fractionOfParent: Double {
        guard let parent, parent.size > 0 else { return 1 }
        return Double(size) / Double(parent.size)
    }
}

/// The result of evaluating a node against the safety rules.
struct SafetyAssessment {
    let level: SafetyLevel
    let reason: String
    let category: CleanupCategory?
}
