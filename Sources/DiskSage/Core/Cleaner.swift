import Foundation
import AppKit

/// Performs the actual reclamation. DiskSage never hard-deletes: everything is
/// moved to the Trash via `FileManager.trashItem`, so any action is reversible
/// by the user from the Finder.
enum Cleaner {
    struct Result {
        var trashedURLs: [URL] = []
        var failed: [(URL, String)] = []
        var bytesFreed: Int64 = 0
    }

    /// Move the given suggestions' files to the Trash. Sizes are summed from the
    /// suggestions (already measured during the scan) for accurate reporting.
    static func clean(_ suggestions: [Suggestion]) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result = Result()
                let fm = FileManager.default
                for suggestion in suggestions {
                    for url in suggestion.urls {
                        guard fm.fileExists(atPath: url.path) else { continue }
                        do {
                            try fm.trashItem(at: url, resultingItemURL: nil)
                            result.trashedURLs.append(url)
                        } catch {
                            result.failed.append((url, error.localizedDescription))
                        }
                    }
                    // Count bytes for fully-trashed suggestions.
                    let allTrashed = suggestion.urls.allSatisfy { result.trashedURLs.contains($0) }
                    if allTrashed { result.bytesFreed += suggestion.size }
                }
                continuation.resume(returning: result)
            }
        }
    }
}
