import Foundation
import CryptoKit

/// Finds byte-for-byte duplicate files in a scanned tree. Cheap by construction:
/// only files that share an exact size are ever hashed, and only above a size
/// threshold (small dupes aren't worth a user's attention). Hashing is content
/// SHA-256 over a streamed read, so results are certain — not a heuristic.
enum DuplicateFinder {
    /// Produce `.duplicateFiles` suggestions: one per set of identical files,
    /// keeping a single copy and offering the rest for removal.
    static func find(root: FileNode,
                     minBytes: Int64 = 50 * 1024 * 1024,
                     home: String) async -> [Suggestion] {
        // Bucket candidate files by exact size.
        var bySize: [Int64: [FileNode]] = [:]
        func collect(_ n: FileNode) {
            if n.isDirectory {
                for c in n.children { collect(c) }
            } else if !n.isSymlink, n.size > 0, n.size >= minBytes {
                // n.size > 0 guards against every empty file hashing alike.
                bySize[n.size, default: []].append(n)
            }
        }
        collect(root)

        let collidingGroups = bySize.values.filter { $0.count >= 2 }
        guard !collidingGroups.isEmpty else { return [] }

        var out: [Suggestion] = []
        for group in collidingGroups {
            if Task.isCancelled { return out }
            // Guard against pathological size collisions (e.g. thousands of
            // equal-size files); hashing them all would be wasteful.
            guard group.count <= 64 else { continue }

            var byHash: [String: [FileNode]] = [:]
            for file in group {
                if Task.isCancelled { return out }
                guard let digest = await Self.hash(url: file.url) else { continue }
                byHash[digest, default: []].append(file)
            }
            for identical in byHash.values where identical.count >= 2 {
                out.append(Self.makeSuggestion(identical, home: home))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// Streamed SHA-256 of a file's contents, off the main actor.
    private static func hash(url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = (try? handle.read(upToCount: 4 * 1024 * 1024)) ?? nil, !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private static func makeSuggestion(_ identical: [FileNode], home: String) -> Suggestion {
        // Keep the copy with the shortest path (usually the most "canonical"
        // location); everything else is redundant.
        let ordered = identical.sorted { $0.path.count < $1.path.count }
        let keep = ordered[0]
        let redundant = Array(ordered.dropFirst())
        let each = keep.size
        let reclaim = each * Int64(redundant.count)

        func short(_ p: String) -> String { p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p }
        let extras = redundant.map(\.path).map(short).joined(separator: "  ·  ")

        return Suggestion(
            category: .duplicateFiles,
            title: "\(identical.count)× \(keep.name)",
            detail: "Keep \(short(keep.path)) — remove: \(extras)",
            size: reclaim,
            safety: .caution,
            reason: "\(identical.count) identical copies (\(ByteFormat.string(each)) each). Keeping one frees \(ByteFormat.string(reclaim)). Make sure the extras aren't deliberate backups before removing.",
            urls: redundant.map(\.url),
            selected: false
        )
    }
}
