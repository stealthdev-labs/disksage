import Testing
import Foundation
@testable import DiskSage

// Uses Swift Testing (`import Testing`) rather than XCTest so the suite runs
// with only the Command Line Tools installed — full Xcode is not required.

private let HOME = "/Users/test"

private func makeEngine() -> SafetyEngine {
    SafetyEngine(home: HOME, oldDownloadDays: 30)
}

/// Build a detached FileNode tree for engine tests.
private func node(_ path: String,
                  dir: Bool = true,
                  size: Int64 = 0,
                  modified: Date? = nil,
                  children: [FileNode] = []) -> FileNode {
    let url = URL(fileURLWithPath: path)
    let n = FileNode(url: url, name: url.lastPathComponent, isDirectory: dir,
                     isSymlink: false, size: size, fileCount: 1, modificationDate: modified)
    for c in children {
        c.parent = n
        n.children.append(c)
    }
    return n
}

@Suite("Safety verdicts")
struct SafetyVerdictTests {
    let engine = makeEngine()

    @Test("System locations are always protected")
    func systemProtected() {
        #expect(engine.assess(path: "/System/Library/Frameworks", name: "Frameworks", isDirectory: true).level == .keep)
        #expect(engine.assess(path: "/usr/bin/zsh", name: "zsh", isDirectory: false).level == .keep)
        #expect(engine.assess(path: "/bin", name: "bin", isDirectory: true).level == .keep)
    }

    @Test("Keychains and app bundles are protected")
    func userCriticalProtected() {
        #expect(engine.assess(path: HOME + "/Library/Keychains/login.keychain-db", name: "login.keychain-db", isDirectory: false).level == .keep)
        #expect(engine.assess(path: HOME + "/Applications/Foo.app", name: "Foo.app", isDirectory: true).level == .keep)
        #expect(engine.assess(path: HOME + "/Movies/Home.photoslibrary", name: "Home.photoslibrary", isDirectory: true).level == .keep)
    }

    @Test("Generic caches and logs are safe")
    func cachesAndLogsSafe() {
        let cache = engine.assess(path: HOME + "/Library/Caches/com.acme.App", name: "com.acme.App", isDirectory: true)
        #expect(cache.level == .safe)
        #expect(cache.category == .userCaches)

        let logs = engine.assess(path: HOME + "/Library/Logs/acme.log", name: "acme.log", isDirectory: false)
        #expect(logs.level == .safe)
        #expect(logs.category == .userLogs)
    }

    @Test(".DS_Store is safe")
    func dsStoreSafe() {
        #expect(engine.assess(path: HOME + "/Documents/.DS_Store", name: ".DS_Store", isDirectory: false).level == .safe)
    }

    @Test("Application Support is caution, unknown user files are kept")
    func ambiguousHandling() {
        #expect(engine.assess(path: HOME + "/Library/Application Support/Acme/db.sqlite", name: "db.sqlite", isDirectory: false).level == .caution)
        #expect(engine.assess(path: HOME + "/Documents/thesis.pages", name: "thesis.pages", isDirectory: false).level == .keep)
    }
}

@Suite("Category classification")
struct CategoryClassificationTests {
    let engine = makeEngine()

    @Test("Known developer/junk folders map to the right category")
    func specificCategories() {
        #expect(engine.specificCategory(path: HOME + "/Library/Developer/Xcode/DerivedData", name: "DerivedData", isDirectory: true) == .xcodeDerivedData)
        #expect(engine.specificCategory(path: HOME + "/dev/app/node_modules", name: "node_modules", isDirectory: true) == .nodeModules)
        #expect(engine.specificCategory(path: HOME + "/.Trash", name: ".Trash", isDirectory: true) == .trash)
        #expect(engine.specificCategory(path: HOME + "/Library/Caches/com.apple.Safari", name: "com.apple.Safari", isDirectory: true) == .browserCache)
        #expect(engine.specificCategory(path: HOME + "/Documents/report.pdf", name: "report.pdf", isDirectory: false) == nil)
    }
}

@Suite("Suggestion collection")
struct SuggestionCollectionTests {
    let engine = makeEngine()

    @Test("Caches root classifies each child and prunes tiny entries")
    func cachesRootExpansion() {
        let big: Int64 = 50 * 1024 * 1024
        let mid: Int64 = 10 * 1024 * 1024
        let tiny: Int64 = 1 * 1024 * 1024
        let caches = node(HOME + "/Library/Caches", size: big + mid + tiny, children: [
            node(HOME + "/Library/Caches/com.apple.Safari", size: big),
            node(HOME + "/Library/Caches/com.acme.App", size: mid),
            node(HOME + "/Library/Caches/tiny", size: tiny)
        ])
        let s = engine.collectSuggestions(root: caches)
        #expect(s.count == 2) // tiny pruned (< 5 MB)
        #expect(s.first?.category == .browserCache) // largest first
        #expect(s.contains { $0.category == .userCaches })
    }

    @Test("A self-contained category folder yields one suggestion and is not descended")
    func selfContainedCategory() {
        let derived = node(HOME + "/Library/Developer/Xcode/DerivedData", size: 200 * 1024 * 1024, children: [
            node(HOME + "/Library/Developer/Xcode/DerivedData/App-abc", size: 200 * 1024 * 1024)
        ])
        let s = engine.collectSuggestions(root: derived)
        #expect(s.count == 1)
        #expect(s.first?.category == .xcodeDerivedData)
    }

    @Test("Scattered .DS_Store files aggregate into a single suggestion")
    func dsStoreAggregation() {
        let tree = node(HOME + "/Projects", children: [
            node(HOME + "/Projects/.DS_Store", dir: false, size: 6 * 1024),
            node(HOME + "/Projects/sub", children: [
                node(HOME + "/Projects/sub/.DS_Store", dir: false, size: 6 * 1024)
            ])
        ])
        let s = engine.collectSuggestions(root: tree)
        let ds = s.first { $0.category == .dsStore }
        #expect(ds != nil)
        #expect(ds?.urls.count == 2)
    }

    @Test("Only stale downloads are flagged")
    func staleDownloads() {
        let old = Date().addingTimeInterval(-60 * 86_400)
        let recent = Date()
        let downloads = node(HOME + "/Downloads", children: [
            node(HOME + "/Downloads/old-installer.dmg", dir: false, size: 20 * 1024 * 1024, modified: old),
            node(HOME + "/Downloads/fresh.zip", dir: false, size: 20 * 1024 * 1024, modified: recent)
        ])
        let s = engine.collectSuggestions(root: downloads)
        #expect(s.count == 1)
        #expect(s.first?.category == .oldDownloads)
        #expect(s.first?.safety == .caution)
    }
}

@Suite("Stale files and app containers")
struct StaleAndContainerTests {
    let engine = makeEngine()

    @Test("Large personal files untouched for a long time are flagged for review")
    func staleLargeFlagged() {
        let old = Date().addingTimeInterval(-400 * 86_400)   // > 12 months
        let recent = Date().addingTimeInterval(-10 * 86_400)
        let big: Int64 = 300 * 1024 * 1024
        let docs = node(HOME + "/Documents", children: [
            node(HOME + "/Documents/old-export.mov", dir: false, size: big, modified: old),
            node(HOME + "/Documents/recent-export.mov", dir: false, size: big, modified: recent),
            node(HOME + "/Documents/small-old.txt", dir: false, size: 1 * 1024 * 1024, modified: old)
        ])
        let s = engine.collectSuggestions(root: docs)
        #expect(s.count == 1)                       // recent + small ones ignored
        #expect(s.first?.category == .staleLargeFiles)
        #expect(s.first?.safety == .caution)
        #expect(s.first?.selected == false)         // never preselected — it's the user's file
        #expect(s.first?.title == "old-export.mov")
    }

    @Test("Files inside a media library are never flagged as loose stale files")
    func bundleInsidesIgnored() {
        let old = Date().addingTimeInterval(-1000 * 86_400)
        let lib = node(HOME + "/Pictures", children: [
            node(HOME + "/Pictures/Photos Library.photoslibrary", children: [
                node(HOME + "/Pictures/Photos Library.photoslibrary/originals/clip.mov",
                     dir: false, size: 500 * 1024 * 1024, modified: old)
            ])
        ])
        #expect(engine.collectSuggestions(root: lib).isEmpty)
    }

    @Test("App-container tmp and caches are recognized as clearable junk")
    func appContainerCaches() {
        #expect(engine.specificCategory(path: HOME + "/Library/Containers/ru.keepcoder.Telegram/Data/tmp",
                                        name: "tmp", isDirectory: true) == .appContainerCache)
        #expect(engine.specificCategory(path: HOME + "/Library/Containers/com.acme.App/Data/Library/Caches",
                                        name: "Caches", isDirectory: true) == .appContainerCache)

        let tree = node(HOME + "/Library/Containers", children: [
            node(HOME + "/Library/Containers/ru.keepcoder.Telegram", children: [
                node(HOME + "/Library/Containers/ru.keepcoder.Telegram/Data", children: [
                    node(HOME + "/Library/Containers/ru.keepcoder.Telegram/Data/tmp",
                         size: 2 * 1024 * 1024 * 1024, children: [
                        node(HOME + "/Library/Containers/ru.keepcoder.Telegram/Data/tmp/video.mp4",
                             dir: false, size: 2 * 1024 * 1024 * 1024)
                    ])
                ])
            ])
        ])
        let s = engine.collectSuggestions(root: tree)
        #expect(s.count == 1)
        #expect(s.first?.category == .appContainerCache)
        #expect(s.first?.safety == .caution)        // another app's data — review, don't preselect
        #expect(s.first?.selected == false)
        #expect(s.first?.title == "Telegram — temporary files")
    }

    @Test("Electron/Chromium caches under Application Support are recognized")
    func electronCaches() {
        #expect(engine.specificCategory(path: HOME + "/Library/Application Support/discord/Code Cache", name: "Code Cache", isDirectory: true) == .appContainerCache)
        #expect(engine.specificCategory(path: HOME + "/Library/Application Support/Code/GPUCache", name: "GPUCache", isDirectory: true) == .appContainerCache)
        #expect(engine.specificCategory(path: HOME + "/Library/Group Containers/group.com.acme/Library/Caches", name: "Caches", isDirectory: true) == .appContainerCache)
        // Real app data under Application Support stays untouched.
        #expect(engine.specificCategory(path: HOME + "/Library/Application Support/discord/Local Storage", name: "Local Storage", isDirectory: true) == nil)
        let support = engine.assess(path: HOME + "/Library/Application Support/discord/Local Storage", name: "Local Storage", isDirectory: true)
        #expect(support.level == .caution)
    }

    @Test("A container's real data store is left alone")
    func containerDataKept() {
        let tree = node(HOME + "/Library/Containers", children: [
            node(HOME + "/Library/Containers/ru.keepcoder.Telegram", children: [
                node(HOME + "/Library/Containers/ru.keepcoder.Telegram/Data", children: [
                    node(HOME + "/Library/Containers/ru.keepcoder.Telegram/Data/postbox", children: [
                        node(HOME + "/Library/Containers/ru.keepcoder.Telegram/Data/postbox/db_sqlite",
                             dir: false, size: 1024 * 1024 * 1024)
                    ])
                ])
            ])
        ])
        #expect(engine.collectSuggestions(root: tree).isEmpty)
    }
}

@Suite("Category invariants")
struct CategoryInvariantTests {
    @Test("Auto-clean only ever targets Safe categories")
    func autoCleanIsAlwaysSafe() {
        for cat in CleanupCategory.allCases where cat.autoCleanEligible {
            #expect(cat.defaultSafety == .safe, "\(cat) is auto-clean eligible but not rated Safe")
        }
    }

    @Test("Every category has non-empty coaching text")
    func explanationsPresent() {
        for cat in CleanupCategory.allCases {
            #expect(!cat.title.isEmpty)
            #expect(cat.explanation.count > 20)
        }
    }
}

@Suite("Duplicate finder")
struct DuplicateFinderTests {
    @Test("Identical files group; same-size-different-content do not")
    func findsDuplicates() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("dsage-dup-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let payload = Data(repeating: 0xAB, count: 4096)
        let other = Data(repeating: 0xCD, count: 4096)        // same size, different bytes
        let urlA = dir.appendingPathComponent("a.bin")
        let urlB = dir.appendingPathComponent("nested/b.bin")
        let urlC = dir.appendingPathComponent("c.bin")
        try payload.write(to: urlA)
        try payload.write(to: urlB)
        try other.write(to: urlC)

        func file(_ url: URL) -> FileNode {
            FileNode(url: url, name: url.lastPathComponent, isDirectory: false,
                     isSymlink: false, size: 4096, fileCount: 1, modificationDate: nil)
        }
        let root = node(dir.path, children: [
            file(urlA),
            node(dir.path + "/nested", children: [file(urlB)]),
            file(urlC)
        ])

        let dupes = await DuplicateFinder.find(root: root, minBytes: 1, home: "/Users/test")
        #expect(dupes.count == 1)                        // only A==B; C excluded by hash
        #expect(dupes.first?.category == .duplicateFiles)
        #expect(dupes.first?.safety == .caution)
        #expect(dupes.first?.urls.count == 1)            // keep one copy, offer the other
        #expect(dupes.first?.size == 4096)
    }

    @Test("Unique files yield nothing")
    func noFalsePositives() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("dsage-uniq-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.bin"); try Data(repeating: 1, count: 2048).write(to: a)
        let b = dir.appendingPathComponent("b.bin"); try Data(repeating: 2, count: 1024).write(to: b)
        let root = node(dir.path, children: [
            FileNode(url: a, name: "a.bin", isDirectory: false, isSymlink: false, size: 2048, fileCount: 1, modificationDate: nil),
            FileNode(url: b, name: "b.bin", isDirectory: false, isSymlink: false, size: 1024, fileCount: 1, modificationDate: nil)
        ])
        let dupes = await DuplicateFinder.find(root: root, minBytes: 1, home: "/Users/test")
        #expect(dupes.isEmpty)
    }
}

@Suite("File kind inference")
struct FileKindTests {
    @Test("Extensions map to coarse kinds")
    func inference() {
        #expect(FileKind.infer(name: "clip.mp4", isDirectory: false) == .video)
        #expect(FileKind.infer(name: "Engine.swift", isDirectory: false) == .code)
        #expect(FileKind.infer(name: "photo.HEIC", isDirectory: false) == .image)
        #expect(FileKind.infer(name: "archive.zip", isDirectory: false) == .archive)
        #expect(FileKind.infer(name: "mystery.qqq", isDirectory: false) == .other)
    }

    @Test("Directories: app bundles vs plain folders")
    func directories() {
        #expect(FileKind.infer(name: "Safari.app", isDirectory: true) == .app)
        #expect(FileKind.infer(name: "Projects", isDirectory: true) == .folder)
    }
}

@Suite("License stub")
struct LicenseTests {
    @Test("The source-build key validates")
    @MainActor
    func demoKeyValid() {
        #expect(LicenseManager.isValid(LicenseManager.demoKey()))
    }

    @Test("Malformed or wrong-checksum keys are rejected")
    @MainActor
    func rejectsBadKeys() {
        #expect(!LicenseManager.isValid("nope"))
        #expect(!LicenseManager.isValid("DSAGE-AB-CD-EF"))          // wrong group lengths
        #expect(!LicenseManager.isValid("DSAGE-OPEN-CORE-ZZZZ"))    // wrong checksum
        #expect(!LicenseManager.isValid("OTHER-OPEN-CORE-" + LicenseManager.checksum("OPENCORE"))) // wrong prefix
    }

    @Test("Checksum is deterministic and 4 chars")
    @MainActor
    func checksumStable() {
        let a = LicenseManager.checksum("OPENCORE")
        #expect(a == LicenseManager.checksum("OPENCORE"))
        #expect(a.count == 4)
    }
}

@Suite("Byte formatting")
struct ByteFormatTests {
    @Test("Zero and negatives render as Zero KB")
    func zeroes() {
        #expect(ByteFormat.string(Int64(0)) == "Zero KB")
        #expect(ByteFormat.string(Int64(-5)) == "Zero KB")
    }

    @Test("Larger values use MB/GB units")
    func units() {
        #expect(ByteFormat.string(Int64(5_000_000)).contains("MB"))
        #expect(ByteFormat.string(Int64(3_000_000_000)).contains("GB"))
    }
}
