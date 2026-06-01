import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case welcome
        case scanning
        case results
    }

    @Published var phase: Phase = .welcome
    @Published var root: FileNode?
    @Published var focus: FileNode?          // current sunburst center
    @Published var hovered: FileNode?        // hovered/selected segment
    @Published var progress = DiskScanner.Progress()
    @Published var scanTargetName = ""
    @Published var suggestions: [Suggestion] = []
    @Published var largestFiles: [FileNode] = []
    @Published var findingDuplicates = false
    @Published var isCleaning = false
    @Published var lastFreed: Int64?
    @Published var banner: String?
    /// Bumped whenever the tree changes structurally, so views recompute layout.
    @Published var revision = 0

    @Published var autoCleanEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCleanEnabled, forKey: "autoCleanEnabled") }
    }
    @Published var autoLastRun: Date?
    @Published var autoLastFreed: Int64?
    @Published var autoRunning = false

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var scanner: DiskScanner?
    private var autoTimer: Timer?
    /// Identifies the current scan so stale async analysis (duplicates) from a
    /// previous scan can't clobber fresh results.
    private var scanToken = UUID()

    init() {
        autoCleanEnabled = UserDefaults.standard.bool(forKey: "autoCleanEnabled")
    }

    var engine: SafetyEngine {
        let days = UserDefaults.standard.object(forKey: "oldDownloadDays") as? Int ?? 30
        let months = UserDefaults.standard.object(forKey: "staleFileMonths") as? Int ?? 12
        var engine = SafetyEngine(home: home, oldDownloadDays: days)
        engine.staleFileMonths = months
        return engine
    }

    // MARK: Volume info

    var volumeFreeBytes: Int64 {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    var volumeTotalBytes: Int64 {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(v?.volumeTotalCapacity ?? 0)
    }

    // MARK: Scanning

    func scanHome() { startScan(url: URL(fileURLWithPath: home), name: "Home") }

    func scanWholeMac() { startScan(url: URL(fileURLWithPath: "/"), name: "Macintosh HD") }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.directoryURL = URL(fileURLWithPath: home)
        if panel.runModal() == .OK, let url = panel.url {
            startScan(url: url, name: url.lastPathComponent)
        }
    }

    func startScan(url: URL, name: String) {
        phase = .scanning
        progress = .init()
        scanTargetName = name
        hovered = nil
        lastFreed = nil
        largestFiles = []
        let token = UUID()
        scanToken = token

        let scanner = DiskScanner()
        self.scanner = scanner
        scanner.onProgress = { p in
            Task { @MainActor in self.progress = p }
        }
        let engine = self.engine

        Task {
            let scannedRoot = await scanner.scan(url: url)
            // Heavy tree analysis off the main actor so the UI stays smooth.
            let (found, largest) = await Task.detached(priority: .userInitiated) {
                (engine.collectSuggestions(root: scannedRoot),
                 Self.topLargestFiles(root: scannedRoot, limit: 200))
            }.value
            guard token == self.scanToken else { return }
            self.root = scannedRoot
            self.focus = scannedRoot
            self.suggestions = found
            self.largestFiles = largest
            self.phase = .results
            self.scanner = nil
            self.findDuplicates(in: scannedRoot, token: token)
        }
    }

    func cancelScan() {
        scanner?.cancel()
        scanner = nil
        scanToken = UUID()      // invalidate any in-flight analysis
        findingDuplicates = false
        phase = .welcome
    }

    /// Flat list of the biggest individual files, largest first.
    nonisolated static func topLargestFiles(root: FileNode, limit: Int) -> [FileNode] {
        var files: [FileNode] = []
        func walk(_ n: FileNode) {
            if n.isDirectory { for c in n.children { walk(c) } }
            else if !n.isSymlink { files.append(n) }
        }
        walk(root)
        return Array(files.sorted { $0.size > $1.size }.prefix(limit))
    }

    /// Hash-based duplicate detection runs after results are shown (it does
    /// real I/O) and folds its findings into the suggestion list when done.
    private func findDuplicates(in root: FileNode, token: UUID) {
        findingDuplicates = true
        let home = self.home
        Task.detached(priority: .utility) {
            let dupes = await DuplicateFinder.find(root: root, home: home)
            await MainActor.run {
                guard token == self.scanToken else { return }
                self.findingDuplicates = false
                guard !dupes.isEmpty else { return }
                self.suggestions.append(contentsOf: dupes)
                self.suggestions.sort { $0.size > $1.size }
            }
        }
    }

    func rescan() {
        guard let root else { return }
        startScan(url: root.url, name: scanTargetName)
    }

    // MARK: Drill-down

    func focusOn(_ node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        focus = node
        hovered = nil
    }

    func goUp() {
        if let parent = focus?.parent, focus?.id != root?.id {
            focus = parent
            hovered = nil
        }
    }

    func breadcrumb() -> [FileNode] {
        guard let focus else { return [] }
        var chain: [FileNode] = []
        var n: FileNode? = focus
        while let cur = n {
            chain.append(cur)
            if cur.id == root?.id { break }
            n = cur.parent
        }
        return chain.reversed()
    }

    // MARK: Cleanup

    var selectedSuggestions: [Suggestion] { suggestions.filter { $0.selected } }
    var selectedReclaim: Int64 { selectedSuggestions.reduce(0) { $0 + $1.size } }
    var totalReclaim: Int64 { suggestions.reduce(0) { $0 + $1.size } }

    func toggle(_ suggestion: Suggestion) {
        guard let idx = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        suggestions[idx].selected.toggle()
    }

    func setAll(selected: Bool, safeOnly: Bool) {
        for i in suggestions.indices {
            suggestions[i].selected = selected && (!safeOnly || suggestions[i].safety == .safe)
        }
    }

    func cleanSelected() async {
        let toClean = selectedSuggestions
        guard !toClean.isEmpty else { return }
        isCleaning = true
        let result = await Cleaner.clean(toClean)
        let trashedIDs = Set(toClean.filter { s in s.urls.allSatisfy { result.trashedURLs.contains($0) } }.map { $0.id })
        suggestions.removeAll { trashedIDs.contains($0.id) }
        let trashedSet = Set(result.trashedURLs.map(\.path))
        largestFiles.removeAll { trashedSet.contains($0.url.path) }
        lastFreed = result.bytesFreed
        isCleaning = false
        if result.failed.isEmpty {
            banner = "Moved \(ByteFormat.string(result.bytesFreed)) to the Trash."
        } else {
            banner = "Freed \(ByteFormat.string(result.bytesFreed)). \(result.failed.count) item(s) couldn't be moved — they may need Full Disk Access."
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Move a single node to the Trash and update the in-memory tree live so the
    /// sunburst and sizes reflect the change without a full rescan.
    func trashNode(_ node: FileNode) async {
        guard node.id != root?.id else { return }
        isCleaning = true
        let url = node.url
        let freed = node.size
        let ok = await Task.detached {
            (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
        }.value
        isCleaning = false
        guard ok else {
            banner = "Couldn't move that item — it may need Full Disk Access."
            return
        }
        detach(node)
        // Match the trashed node itself or anything genuinely beneath it — guard
        // the separator so "…/foo" doesn't also match a sibling "…/foobar".
        let trashedPath = url.path
        let trashedPrefix = trashedPath + "/"
        suggestions.removeAll { $0.urls.contains { $0.path == trashedPath || $0.path.hasPrefix(trashedPrefix) } }
        largestFiles.removeAll { $0.url.path == trashedPath || $0.url.path.hasPrefix(trashedPrefix) }
        if hovered?.id == node.id { hovered = nil }
        revision += 1
        banner = "Moved \(ByteFormat.string(freed)) to the Trash."
    }

    private func detach(_ node: FileNode) {
        guard let parent = node.parent else { return }
        parent.children.removeAll { $0.id == node.id }
        var ancestor: FileNode? = parent
        while let cur = ancestor {
            cur.size -= node.size
            cur.fileCount -= node.fileCount
            ancestor = cur.parent
        }
    }

    // MARK: Auto-clean (Pro)

    /// The conservative set of roots auto-clean is allowed to sweep. Only places
    /// that hold regenerable junk — never user documents or project folders.
    private func autoCleanRoots() -> [URL] {
        [
            home + "/Library/Caches",
            home + "/Library/Logs",
            home + "/Library/Developer/Xcode/DerivedData"
        ].map { URL(fileURLWithPath: $0) }
    }

    /// Called on launch and whenever the toggle / Pro status changes.
    func configureAutoClean(isPro: Bool) {
        autoTimer?.invalidate()
        autoTimer = nil
        guard isPro, autoCleanEnabled else { return }
        Task { await runAutoCleanSweep() }
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runAutoCleanSweep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
    }

    func runAutoCleanSweep() async {
        guard !autoRunning else { return }
        autoRunning = true
        defer { autoRunning = false }

        let engine = self.engine
        var freed: Int64 = 0
        for root in autoCleanRoots() where FileManager.default.fileExists(atPath: root.path) {
            let scanner = DiskScanner()
            let node = await scanner.scan(url: root)
            let safe = engine.collectSuggestions(root: node)
                .filter { $0.safety == .safe && $0.category.autoCleanEligible }
            guard !safe.isEmpty else { continue }
            let result = await Cleaner.clean(safe)
            freed += result.bytesFreed
        }
        autoLastRun = Date()
        autoLastFreed = freed
        if freed > 0 { banner = "Auto-clean freed \(ByteFormat.string(freed))." }
    }
}
