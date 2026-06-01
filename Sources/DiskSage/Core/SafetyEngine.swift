import Foundation

/// A concrete, actionable cleanup recommendation surfaced to the user.
/// Decoupled from `FileNode` so it can represent a single folder, one of many
/// app-cache subfolders, or an aggregate of scattered files (e.g. .DS_Store).
struct Suggestion: Identifiable {
    let id = UUID()
    let category: CleanupCategory
    let title: String
    let detail: String
    let size: Int64
    let safety: SafetyLevel
    let reason: String
    let urls: [URL]
    var selected: Bool
}

/// The rules engine. Entirely local and deterministic: no network, no model
/// weights — just curated knowledge of the macOS filesystem encoded as path
/// rules plus a few heuristics. This is the "AI advisor" that tells the user
/// what is safe, what to review, and what to never touch.
struct SafetyEngine {
    let home: String
    /// Items in ~/Downloads older than this many days are flagged as stale.
    var oldDownloadDays: Int = 30
    /// Large files in personal folders untouched for this many months are
    /// flagged for review. 0 disables the check.
    var staleFileMonths: Int = 12
    /// Only personal files at least this big are considered "stale & large".
    var staleLargeBytes: Int64 = 200 * 1024 * 1024
    /// Suggestions smaller than this are hidden as noise (bytes).
    var minSuggestionBytes: Int64 = 5 * 1024 * 1024

    init(home: String = FileManager.default.homeDirectoryForCurrentUser.path,
         oldDownloadDays: Int = 30) {
        self.home = home.hasSuffix("/") ? String(home.dropLast()) : home
        self.oldDownloadDays = oldDownloadDays
    }

    // MARK: Roots (computed once)

    private var cachesRoot: String { home + "/Library/Caches" }
    private var logsRoot: String { home + "/Library/Logs" }
    private var downloadsRoot: String { home + "/Downloads" }
    private var xcodeRoot: String { home + "/Library/Developer/Xcode" }

    // MARK: Per-node classification

    /// Match a node against the *specific* known categories. Returns nil for
    /// generic cache/log folders (handled at the container level) and for
    /// everything that isn't a recognized cleanup target.
    func specificCategory(path: String, name: String, isDirectory: Bool) -> CleanupCategory? {
        // Developer tooling
        if path == xcodeRoot + "/DerivedData" { return .xcodeDerivedData }
        if path == xcodeRoot + "/Archives" { return .xcodeArchives }
        if isDirectory, path.hasPrefix(xcodeRoot + "/"), name.contains("DeviceSupport") { return .xcodeDeviceSupport }
        if path == home + "/Library/Developer/CoreSimulator" { return .coreSimulator }

        if isDirectory, name == "node_modules" { return .nodeModules }
        if path == cachesRoot + "/Homebrew" || path == home + "/Library/Homebrew" { return .homebrewCache }
        if path == home + "/.npm" || name == "_cacache" && path.contains("/.npm") { return .npmCache }
        if path == cachesRoot + "/Yarn" || path == home + "/.yarn/cache" || path == home + "/.cache/yarn" { return .yarnCache }
        if path == home + "/Library/pnpm/store" || path == home + "/.pnpm-store" || path == home + "/.local/share/pnpm/store" { return .pnpmStore }
        if path == cachesRoot + "/pip" || path == home + "/.cache/pip" { return .pipCache }
        if path == home + "/.gradle/caches" { return .gradleCache }
        if path == home + "/.cargo/registry" { return .cargoRegistry }
        if path == cachesRoot + "/go-build" { return .goBuildCache }

        // Docker
        if path == home + "/Library/Containers/com.docker.docker" { return .dockerData }

        // App-sandbox temporary & cache data. Modern sandboxed / Electron apps
        // (Telegram, Discord, Slack, VS Code, browsers…) hide large, regenerable
        // piles under their container or Application Support — chat videos in
        // .../Data/tmp, Chromium "Code Cache"/"GPUCache", etc. — that the generic
        // ~/Library/Caches rule never reaches.
        if isDirectory {
            let underAppArea = path.hasPrefix(home + "/Library/Containers/")
                || path.hasPrefix(home + "/Library/Group Containers/")
                || path.hasPrefix(home + "/Library/Application Support/")
            if underAppArea {
                if Self.regenerableCacheDirs.contains(name) { return .appContainerCache }
                if name == "tmp", path.hasPrefix(home + "/Library/Containers/") { return .appContainerCache }
            }
        }

        // Logs & diagnostics
        if name == "DiagnosticReports", path.hasPrefix(home + "/Library/Logs") || path.hasPrefix("/Library/Logs") { return .crashReports }
        if path == "/Library/Logs" || path == "/var/log" { return .systemLogs }

        // Trash & backups
        if path == home + "/.Trash" { return .trash }
        if path == home + "/Library/Application Support/MobileSync/Backup" { return .iosBackups }

        // Mail & previews
        if name == "Mail Downloads" { return .mailDownloads }
        if isDirectory, name.contains("com.apple.QuickLook") { return .quickLookCache }

        // Browser caches (when reached directly under Caches)
        if path.hasPrefix(cachesRoot + "/"), Self.browserCacheLeaves.contains(where: { name == $0 || name.hasPrefix($0) }) {
            return .browserCache
        }

        return nil
    }

    private static let browserCacheLeaves: Set<String> = [
        "com.apple.Safari", "Google", "com.google.Chrome", "Firefox",
        "org.mozilla.firefox", "com.microsoft.edgemac", "BraveSoftware", "com.operasoftware.Opera"
    ]

    private static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple", "/cores", "/Network", "/.vol"]
    private static let keepSuffixes = [".app", ".framework", ".kext", ".bundle", ".plugin", ".photoslibrary", ".fcpbundle", ".imovielibrary", ".musiclibrary", ".tvlibrary", ".aplibrary", ".pkg"]

    /// Path markers for bundles/libraries whose *insides* we must never flag as
    /// loose files (a 4 GB clip inside a Photos library isn't "an old file").
    private static let bundleMarkers = [".app/", ".framework/", ".bundle/", ".plugin/", ".photoslibrary/",
                                        ".fcpbundle/", ".imovielibrary/", ".musiclibrary/", ".tvlibrary/",
                                        ".aplibrary/", ".photolibrary/", ".pkg/"]

    private static func isInsideProtectedBundle(_ path: String) -> Bool {
        bundleMarkers.contains { path.contains($0) }
    }

    /// Folder names that are, by strong convention, regenerable caches —
    /// Chromium/Electron and friends scatter these inside app sandboxes.
    private static let regenerableCacheDirs: Set<String> = [
        "Cache", "Caches", "Code Cache", "GPUCache", "GrShaderCache",
        "ShaderCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "ComponentCrx", "Crashpad", "CachedData"
    ]

    /// The advisory verdict used for coloring and detail views. Cheap to call
    /// per node. Order matters: most specific / most protective rules first.
    func assess(path: String, name: String, isDirectory: Bool) -> SafetyAssessment {
        if let cat = specificCategory(path: path, name: name, isDirectory: isDirectory) {
            return SafetyAssessment(level: cat.defaultSafety, reason: cat.explanation, category: cat)
        }

        // Never touch system locations.
        for p in Self.systemPrefixes where path == p || path.hasPrefix(p + "/") {
            return SafetyAssessment(level: .keep, reason: "System file. macOS needs this — DiskSage will never remove it.", category: nil)
        }
        if path == home + "/Library/Keychains" || path.hasPrefix(home + "/Library/Keychains/") {
            return SafetyAssessment(level: .keep, reason: "Your keychains and passwords. Never delete.", category: nil)
        }
        for s in Self.keepSuffixes where name.hasSuffix(s) {
            return SafetyAssessment(level: .keep, reason: "An installed app or media library bundle. Remove it through its app or the App Store, not here.", category: nil)
        }

        // Generic caches / logs that didn't match a specific tool.
        if path == cachesRoot || path.hasPrefix(cachesRoot + "/") {
            return SafetyAssessment(level: .safe, reason: CleanupCategory.userCaches.explanation, category: .userCaches)
        }
        if path == logsRoot || path.hasPrefix(logsRoot + "/") {
            return SafetyAssessment(level: .safe, reason: CleanupCategory.userLogs.explanation, category: .userLogs)
        }
        if name == ".DS_Store" {
            return SafetyAssessment(level: .safe, reason: CleanupCategory.dsStore.explanation, category: .dsStore)
        }

        // Application Support is a mixed bag — real data lives here.
        if path.hasPrefix(home + "/Library/Application Support/") {
            return SafetyAssessment(level: .caution, reason: "App support data. Some apps keep real, irreplaceable data here — review before deleting.", category: nil)
        }

        // Everything else under the user's home that we don't recognize: assume
        // it's the user's own work and protect it.
        if path.hasPrefix(home + "/") {
            return SafetyAssessment(level: .keep, reason: "Looks like your own file. DiskSage won't suggest deleting it.", category: nil)
        }

        return SafetyAssessment(level: .caution, reason: "Unrecognized location — review before deleting.", category: nil)
    }

    func assess(_ node: FileNode) -> SafetyAssessment {
        assess(path: node.path, name: node.name, isDirectory: node.isDirectory)
    }

    // MARK: Suggestion collection

    /// Walk the scanned tree and produce a deduplicated set of cleanup
    /// suggestions. Prunes aggressively: once a folder is recognized as a unit
    /// (e.g. node_modules), its contents are not descended into.
    func collectSuggestions(root: FileNode) -> [Suggestion] {
        var out: [Suggestion] = []
        var dsStoreURLs: [URL] = []
        var dsStoreBytes: Int64 = 0
        let staleCutoff = Date().addingTimeInterval(-Double(oldDownloadDays) * 86_400)

        // Large, untouched personal files (the "you forgot this was here" pile).
        let staleLargeCutoff = Date().addingTimeInterval(-Double(staleFileMonths) * 30 * 86_400)
        let personalRoots = ["Desktop", "Documents", "Movies", "Music", "Pictures"]
            .map { home + "/" + $0 + "/" }

        func makeSuggestion(node: FileNode, category: CleanupCategory, titleOverride: String? = nil) -> Suggestion {
            let title: String
            switch category {
            case .userCaches, .userLogs, .browserCache, .oldDownloads:
                title = node.name
            case .appContainerCache:
                title = containerAppName(node.path) + (node.name == "tmp" ? " — temporary files" : " — cache")
            default:
                title = category.title
            }
            return Suggestion(
                category: category,
                title: titleOverride ?? title,
                detail: shorten(node.path),
                size: node.size,
                safety: category.defaultSafety,
                reason: category.explanation,
                urls: [node.url],
                selected: category.defaultSafety == .safe
            )
        }

        func walk(_ node: FileNode) {
            let path = node.path

            // Aggregate scattered .DS_Store files.
            if node.name == ".DS_Store" {
                dsStoreURLs.append(node.url)
                dsStoreBytes += node.size
                return
            }

            // Container roots: classify each immediate child instead of the whole folder.
            if path == cachesRoot || path == logsRoot {
                for child in node.children {
                    let cat = specificCategory(path: child.path, name: child.name, isDirectory: child.isDirectory)
                        ?? (path == cachesRoot ? .userCaches : .userLogs)
                    if child.size >= minSuggestionBytes {
                        out.append(makeSuggestion(node: child, category: cat))
                    }
                }
                return
            }

            // Stale downloads.
            if path == downloadsRoot {
                for child in node.children {
                    if let m = child.modificationDate, m < staleCutoff, child.size >= minSuggestionBytes {
                        out.append(Suggestion(
                            category: .oldDownloads,
                            title: child.name,
                            detail: relativeAge(child.modificationDate),
                            size: child.size,
                            safety: .caution,
                            reason: CleanupCategory.oldDownloads.explanation,
                            urls: [child.url],
                            selected: false
                        ))
                    }
                }
                return
            }

            // A recognized, self-contained category folder.
            if let cat = specificCategory(path: path, name: node.name, isDirectory: node.isDirectory) {
                if node.size >= minSuggestionBytes || cat == .trash {
                    out.append(makeSuggestion(node: node, category: cat))
                }
                return // do not descend into a unit
            }

            // Large personal files left untouched for a long time — only loose
            // files nothing more specific claimed. Gated on size first so the
            // path work runs only for the rare big file.
            if staleFileMonths > 0, !node.isDirectory, node.size >= staleLargeBytes,
               let m = node.modificationDate, m < staleLargeCutoff,
               personalRoots.contains(where: { path.hasPrefix($0) }),
               !Self.isInsideProtectedBundle(path) {
                out.append(Suggestion(
                    category: .staleLargeFiles,
                    title: node.name,
                    detail: relativeAge(m) + " · " + shorten(node.path),
                    size: node.size,
                    safety: .caution,
                    reason: CleanupCategory.staleLargeFiles.explanation,
                    urls: [node.url],
                    selected: false
                ))
                return
            }

            for child in node.children { walk(child) }
        }

        walk(root)

        if dsStoreBytes > 0 || !dsStoreURLs.isEmpty {
            out.append(Suggestion(
                category: .dsStore,
                title: "\(dsStoreURLs.count) .DS_Store files",
                detail: "Scattered across scanned folders",
                size: dsStoreBytes,
                safety: .safe,
                reason: CleanupCategory.dsStore.explanation,
                urls: dsStoreURLs,
                selected: true
            ))
        }

        return out.sorted { $0.size > $1.size }
    }

    // MARK: Helpers

    private func shorten(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Friendly app name from a sandbox/support path:
    /// "~/Library/Containers/ru.keepcoder.Telegram/Data/tmp" -> "Telegram",
    /// "~/Library/Application Support/discord/GPUCache" -> "Discord".
    private func containerAppName(_ path: String) -> String {
        for marker in ["/Library/Containers/", "/Library/Group Containers/", "/Library/Application Support/"] {
            guard let r = path.range(of: marker) else { continue }
            let seg = path[r.upperBound...].split(separator: "/").first.map(String.init) ?? "App"
            let last = seg.split(separator: ".").last.map(String.init) ?? seg
            return last.isEmpty ? seg : last.prefix(1).uppercased() + last.dropFirst()
        }
        return "App"
    }

    private func relativeAge(_ date: Date?) -> String {
        guard let date else { return "" }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days >= 365 { return "Untouched for \(days / 365)y" }
        if days >= 30 { return "Untouched for \(days / 30)mo" }
        return "Untouched for \(days)d"
    }
}
