import Foundation

/// Recursive, concurrent filesystem scanner. The shallowest levels — where a
/// handful of enormous subtrees (`~/Library`, `/System`, `/Users`) would
/// otherwise each pin a single core — fan their children out across the
/// cooperative pool; deeper recursion is synchronous to avoid spawning a task
/// per directory. Uses allocated (physical) size via URL resource values.
final class DiskScanner {
    struct Progress {
        var filesScanned: Int = 0
        var bytesScanned: Int64 = 0
        var currentPath: String = ""
    }

    private let fm = FileManager.default
    private let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey
    ]
    private lazy var keyArray = Array(keys)

    /// How many levels recurse in parallel before switching to synchronous
    /// descent. Levels 0 and 1 cover the few giant top-level subtrees and their
    /// immediate children (e.g. `~/Library/{Caches,Containers,Developer}`),
    /// which is where the win is; going deeper just multiplies task overhead.
    private let parallelDepth = 2

    /// Synthetic / firmlinked mount points that re-expose content already
    /// reachable from the scan root. On modern macOS the data volume is
    /// firmlinked into `/`, so `/System/Volumes/Data` and `/Volumes/<bootdisk>`
    /// duplicate the *entire* disk — descending into them double- or
    /// triple-counts everything and triples scan time. `/dev` is synthetic
    /// device nodes, not real storage. Skipped as children only, so choosing
    /// one of these as an explicit scan root still works.
    private let skipPaths: Set<String> = [
        "/System/Volumes/Data",
        "/Volumes",
        "/dev"
    ]

    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var lastPath = ""
    private var cancelledFlag = false

    var onProgress: ((Progress) -> Void)?

    func cancel() {
        lock.lock(); cancelledFlag = true; lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return cancelledFlag
    }

    private func resetCounters() {
        lock.lock(); files = 0; bytes = 0; lastPath = ""; cancelledFlag = false; lock.unlock()
    }

    func scan(url: URL) async -> FileNode {
        resetCounters()
        let node = await scanNode(url, depth: 0) ?? FileNode(
            url: url, name: url.lastPathComponent, isDirectory: true,
            isSymlink: false, size: 0, fileCount: 0, modificationDate: nil)
        emit(force: true)
        return node
    }

    /// Builds the node for `url`. Directories above `parallelDepth` fan their
    /// children across the cooperative pool; below it they recurse synchronously.
    private func scanNode(_ url: URL, depth: Int) async -> FileNode? {
        if isCancelled { return nil }
        guard let rv = try? url.resourceValues(forKeys: keys) else { return nil }

        guard (rv.isDirectory ?? false) && !(rv.isSymbolicLink ?? false) else {
            return fileNode(url: url, rv: rv)
        }
        if depth >= parallelDepth {
            return scanSync(url, rv: rv)
        }

        let node = directoryNode(url: url, rv: rv)
        guard let contents = childURLs(of: url, marking: node) else { return node }

        await withTaskGroup(of: FileNode?.self) { group in
            for child in contents {
                group.addTask(priority: .userInitiated) { [weak self] in
                    await self?.scanNode(child, depth: depth + 1) ?? nil
                }
            }
            for await child in group {
                attach(child, to: node)
            }
        }
        bump(files: 0, bytes: 0, path: url.path)
        return node
    }

    /// Synchronous deep recursion — a single task walks the whole subtree.
    private func scanSync(_ url: URL, rv prefetched: URLResourceValues? = nil) -> FileNode? {
        if isCancelled { return nil }
        guard let rv = prefetched ?? (try? url.resourceValues(forKeys: keys)) else { return nil }

        guard (rv.isDirectory ?? false) && !(rv.isSymbolicLink ?? false) else {
            return fileNode(url: url, rv: rv)
        }
        let node = directoryNode(url: url, rv: rv)
        guard let contents = childURLs(of: url, marking: node) else { return node }
        for childURL in contents {
            attach(scanSync(childURL), to: node)
        }
        bump(files: 0, bytes: 0, path: url.path)
        return node
    }

    // MARK: Node construction

    private func directoryNode(url: URL, rv: URLResourceValues) -> FileNode {
        FileNode(url: url, name: url.lastPathComponent, isDirectory: true, isSymlink: false,
                 size: 0, fileCount: 0, modificationDate: rv.contentModificationDate)
    }

    /// Builds a leaf node (regular file or symlink) and records it in progress.
    private func fileNode(url: URL, rv: URLResourceValues) -> FileNode {
        let size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0)
        let node = FileNode(url: url, name: url.lastPathComponent, isDirectory: false,
                            isSymlink: rv.isSymbolicLink ?? false, size: size, fileCount: 1,
                            modificationDate: rv.contentModificationDate)
        bump(files: 1, bytes: size, path: url.path)
        return node
    }

    /// Lists `url`'s children, dropping firmlink/synthetic duplicates. Marks the
    /// node partial and returns nil when the directory can't be read.
    private func childURLs(of url: URL, marking node: FileNode) -> [URL]? {
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keyArray, options: []) else {
            node.isPartial = true
            return nil
        }
        return skipPaths.isEmpty ? contents : contents.filter { !skipPaths.contains($0.path) }
    }

    private func attach(_ child: FileNode?, to parent: FileNode) {
        guard let child else { return }
        child.parent = parent
        parent.children.append(child)
        parent.size += child.size
        parent.fileCount += child.fileCount
        parent.isPartial = parent.isPartial || child.isPartial
    }

    // MARK: Progress

    private func bump(files deltaFiles: Int, bytes deltaBytes: Int64, path: String) {
        lock.lock()
        files += deltaFiles
        bytes += deltaBytes
        lastPath = path
        let shouldEmit = files % 1500 == 0
        let snapshot = Progress(filesScanned: files, bytesScanned: bytes, currentPath: path)
        lock.unlock()
        if shouldEmit { onProgress?(snapshot) }
    }

    private func emit(force: Bool) {
        lock.lock()
        let snapshot = Progress(filesScanned: files, bytesScanned: bytes, currentPath: lastPath)
        lock.unlock()
        onProgress?(snapshot)
    }
}
