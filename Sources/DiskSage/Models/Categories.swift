import SwiftUI

// MARK: - FileKind (for visualization coloring)

/// Coarse classification of a file used to color the sunburst, à la DaisyDisk.
enum FileKind: String {
    case folder
    case video
    case audio
    case image
    case code
    case archive
    case document
    case app
    case binary
    case other

    var color: Color {
        switch self {
        case .folder:   return Color(red: 0.40, green: 0.45, blue: 0.55)
        case .video:    return Color(red: 0.90, green: 0.34, blue: 0.45)
        case .audio:    return Color(red: 0.95, green: 0.61, blue: 0.25)
        case .image:    return Color(red: 0.36, green: 0.72, blue: 0.55)
        case .code:     return Color(red: 0.36, green: 0.58, blue: 0.92)
        case .archive:  return Color(red: 0.66, green: 0.49, blue: 0.86)
        case .document: return Color(red: 0.30, green: 0.66, blue: 0.78)
        case .app:      return Color(red: 0.55, green: 0.60, blue: 0.66)
        case .binary:   return Color(red: 0.58, green: 0.53, blue: 0.45)
        case .other:    return Color(red: 0.50, green: 0.54, blue: 0.60)
        }
    }

    var label: String {
        switch self {
        case .folder:   return "Folders"
        case .video:    return "Video"
        case .audio:    return "Audio"
        case .image:    return "Images"
        case .code:     return "Code"
        case .archive:  return "Archives"
        case .document: return "Docs"
        case .app:      return "Apps"
        case .binary:   return "Binaries"
        case .other:    return "Other"
        }
    }

    /// The kinds worth showing in the chart legend, in a sensible reading order.
    static let legendOrder: [FileKind] = [.folder, .video, .audio, .image, .document, .code, .archive, .app, .other]

    static func infer(name: String, isDirectory: Bool) -> FileKind {
        if isDirectory {
            if name.hasSuffix(".app") || name.hasSuffix(".framework") { return .app }
            return .folder
        }
        let ext = (name as NSString).pathExtension.lowercased()
        if Self.videoExt.contains(ext) { return .video }
        if Self.audioExt.contains(ext) { return .audio }
        if Self.imageExt.contains(ext) { return .image }
        if Self.codeExt.contains(ext) { return .code }
        if Self.archiveExt.contains(ext) { return .archive }
        if Self.documentExt.contains(ext) { return .document }
        if Self.binaryExt.contains(ext) { return .binary }
        return .other
    }

    private static let videoExt: Set<String> = ["mp4", "mov", "mkv", "avi", "m4v", "webm", "wmv", "flv", "mpg", "mpeg", "hevc"]
    private static let audioExt: Set<String> = ["mp3", "aac", "wav", "flac", "m4a", "aiff", "ogg", "alac", "wma"]
    private static let imageExt: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "raw", "cr2", "nef", "psd", "svg", "webp"]
    private static let codeExt: Set<String> = ["swift", "c", "h", "m", "mm", "cpp", "cc", "hpp", "js", "ts", "jsx", "tsx", "py", "rb", "go", "rs", "java", "kt", "php", "html", "css", "json", "xml", "yml", "yaml", "sh", "sql"]
    private static let archiveExt: Set<String> = ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "iso", "tgz", "zst"]
    private static let documentExt: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "md", "rtf", "epub", "csv"]
    private static let binaryExt: Set<String> = ["o", "a", "so", "dylib", "bin", "exe", "wasm", "class", "pyc"]
}

// MARK: - SafetyLevel (the core "AI" verdict)

/// The advisory verdict for a file or folder. This is what makes DiskSage a
/// *coach* rather than a blunt cleaner: every item carries one of these.
enum SafetyLevel: Int, Comparable {
    case keep = 0      // never recommend deleting — system or irreplaceable user data
    case caution = 1   // can be deleted, but think first — may contain real data
    case safe = 2      // regenerable junk — safe to remove, app will rebuild it

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .keep:    return "Keep"
        case .caution: return "Review"
        case .safe:    return "Safe to delete"
        }
    }

    var systemImage: String {
        switch self {
        case .keep:    return "lock.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .safe:    return "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .keep:    return Color(red: 0.90, green: 0.30, blue: 0.34)
        case .caution: return Color(red: 0.95, green: 0.70, blue: 0.20)
        case .safe:    return Color(red: 0.30, green: 0.78, blue: 0.46)
        }
    }

    var shortNote: String {
        switch self {
        case .keep:    return "Deleting this could break apps or lose data."
        case .caution: return "Deletable, but may hold files you want."
        case .safe:    return "Regenerable junk — frees space with no downside."
        }
    }
}

// MARK: - CleanupCategory (smart categories with human explanations)

/// Known, well-understood buckets of reclaimable space. Each carries the
/// plain-language explanation DiskSage shows the user ("what is this, and why
/// is it safe?"). Paths are validated against this list in `SafetyEngine`.
enum CleanupCategory: String, CaseIterable, Identifiable {
    case xcodeDerivedData
    case xcodeArchives
    case xcodeDeviceSupport
    case coreSimulator
    case homebrewCache
    case npmCache
    case nodeModules
    case yarnCache
    case pnpmStore
    case pipCache
    case gradleCache
    case cargoRegistry
    case goBuildCache
    case dockerData
    case userCaches
    case appContainerCache
    case browserCache
    case userLogs
    case systemLogs
    case crashReports
    case trash
    case iosBackups
    case oldDownloads
    case staleLargeFiles
    case duplicateFiles
    case mailDownloads
    case quickLookCache
    case tmpClutter
    case dsStore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcodeDerivedData:  return "Xcode DerivedData"
        case .xcodeArchives:     return "Xcode Archives"
        case .xcodeDeviceSupport:return "Xcode Device Support"
        case .coreSimulator:     return "iOS Simulator Data"
        case .homebrewCache:     return "Homebrew Cache"
        case .npmCache:          return "npm Cache"
        case .nodeModules:       return "node_modules"
        case .yarnCache:         return "Yarn Cache"
        case .pnpmStore:         return "pnpm Store"
        case .pipCache:          return "pip Cache"
        case .gradleCache:       return "Gradle Cache"
        case .cargoRegistry:     return "Cargo Registry"
        case .goBuildCache:      return "Go Build Cache"
        case .dockerData:        return "Docker Data"
        case .userCaches:        return "App Caches"
        case .appContainerCache: return "App Container Caches"
        case .browserCache:      return "Browser Cache"
        case .userLogs:          return "App Logs"
        case .systemLogs:        return "System Logs"
        case .crashReports:      return "Crash Reports"
        case .trash:             return "Trash"
        case .iosBackups:        return "Old iOS Backups"
        case .oldDownloads:      return "Old Downloads"
        case .staleLargeFiles:   return "Old, Large Files"
        case .duplicateFiles:    return "Duplicate Files"
        case .mailDownloads:     return "Mail Attachments"
        case .quickLookCache:    return "Quick Look Cache"
        case .tmpClutter:        return "Temporary Files"
        case .dsStore:           return ".DS_Store Files"
        }
    }

    /// The plain-language coaching text. This is the heart of the "AI advisor".
    var explanation: String {
        switch self {
        case .xcodeDerivedData:
            return "Xcode's build intermediates and indexes. Xcode rebuilds them on the next build. Classic dead weight — often 10–100 GB."
        case .xcodeArchives:
            return "Saved app archives from past builds. Safe to remove unless you still need to re-export a specific old build for the App Store."
        case .xcodeDeviceSupport:
            return "Debug symbols for iOS versions you connected once. Re-downloaded automatically when you plug a device back in."
        case .coreSimulator:
            return "iOS Simulator devices and their data. Removing frees lots of space; simulators are recreated on demand (you'll re-install test apps)."
        case .homebrewCache:
            return "Downloaded bottles/formulae Homebrew already installed. Pure cache — `brew` re-downloads if ever needed."
        case .npmCache:
            return "npm's global download cache. Fully regenerable; npm refetches packages as needed."
        case .nodeModules:
            return "Project dependencies. Safe ONLY if you can run `npm install` again. Reclaims huge space across old projects."
        case .yarnCache:
            return "Yarn's global package cache. Regenerable on the next install."
        case .pnpmStore:
            return "pnpm's content-addressable store. Regenerable, but shared across projects — removing forces re-download for all of them."
        case .pipCache:
            return "Python pip's wheel/download cache. Regenerable automatically."
        case .gradleCache:
            return "Gradle's downloaded dependencies and build cache. Re-downloaded on next build."
        case .cargoRegistry:
            return "Rust Cargo's cached crate sources. Re-fetched on next build."
        case .goBuildCache:
            return "Go's build cache. Rebuilt automatically; safe to clear."
        case .dockerData:
            return "Docker images, containers and volumes. Can be enormous, but may hold data/images you can't easily rebuild — review first."
        case .userCaches:
            return "Per-app caches under ~/Library/Caches. Apps recreate them; expect a one-time slowdown as caches warm up again."
        case .appContainerCache:
            return "Temporary and cache data inside a sandboxed app's container — like videos a chat app re-downloads on demand. Often surprisingly large and regenerable, but it's another app's data, so DiskSage flags it for review rather than preselecting it."
        case .browserCache:
            return "Cached web pages and assets. Browsers rebuild them; you may need to log back into some sites."
        case .userLogs:
            return "Application log files. Diagnostic only — safe to delete unless you're actively debugging an app."
        case .systemLogs:
            return "System and diagnostic logs. Generally safe, but keep them if you're chasing a system bug."
        case .crashReports:
            return "Saved crash and diagnostic reports. Safe to delete unless you're investigating a specific crash."
        case .trash:
            return "The Trash itself. Emptying permanently frees this space."
        case .iosBackups:
            return "Local iPhone/iPad backups via Finder. Often 10–200 GB. Delete ONLY if you have iCloud or another backup."
        case .oldDownloads:
            return "Items in ~/Downloads untouched for a long time. Often installers and one-off files — but glance through first."
        case .staleLargeFiles:
            return "Big files in your personal folders you haven't changed in a long time — old installers, disk images, exports, videos. These are your files, so DiskSage only flags them for review and never auto-removes them."
        case .duplicateFiles:
            return "Byte-for-byte identical copies of the same file in more than one place. DiskSage keeps one and offers the redundant copies for removal — check they aren't deliberate backups first."
        case .mailDownloads:
            return "Saved Mail attachments cache. Re-downloaded from the server when you open the message again."
        case .quickLookCache:
            return "Thumbnail/preview cache. Rebuilt instantly as you browse files."
        case .tmpClutter:
            return "Stale temporary files. Safe to clear; apps recreate what they need."
        case .dsStore:
            return "Finder's hidden per-folder metadata. Harmless to delete; Finder recreates them."
        }
    }

    var defaultSafety: SafetyLevel {
        switch self {
        case .nodeModules, .pnpmStore, .oldDownloads, .staleLargeFiles, .duplicateFiles,
             .appContainerCache, .iosBackups, .dockerData, .systemLogs:
            return .caution
        default:
            return .safe
        }
    }

    var systemImage: String {
        switch self {
        case .xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport, .coreSimulator:
            return "hammer.fill"
        case .homebrewCache, .npmCache, .nodeModules, .yarnCache, .pnpmStore,
             .pipCache, .gradleCache, .cargoRegistry, .goBuildCache:
            return "shippingbox.fill"
        case .dockerData:
            return "cube.box.fill"
        case .userCaches, .appContainerCache, .browserCache, .quickLookCache:
            return "internaldrive.fill"
        case .userLogs, .systemLogs, .crashReports:
            return "doc.text.fill"
        case .trash:
            return "trash.fill"
        case .iosBackups:
            return "iphone"
        case .oldDownloads:
            return "arrow.down.circle.fill"
        case .staleLargeFiles:
            return "clock.badge.exclamationmark.fill"
        case .duplicateFiles:
            return "doc.on.doc.fill"
        case .mailDownloads:
            return "envelope.fill"
        case .tmpClutter, .dsStore:
            return "sparkles"
        }
    }

    /// Only categories that are unambiguously regenerable junk are eligible for
    /// hands-off, scheduled auto-clean (a Pro feature).
    var autoCleanEligible: Bool {
        switch self {
        case .xcodeDerivedData, .homebrewCache, .npmCache, .yarnCache, .pipCache,
             .goBuildCache, .userCaches, .browserCache, .userLogs, .crashReports,
             .quickLookCache, .tmpClutter, .dsStore, .mailDownloads:
            return true
        default:
            return false
        }
    }
}
