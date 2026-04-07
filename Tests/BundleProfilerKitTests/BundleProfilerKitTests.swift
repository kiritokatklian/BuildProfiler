//
//  BundleProfilerKitTests.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation
import Testing

@testable import BundleProfilerKit

@Suite("FileCategory Tests")
struct FileCategoryTests {
    @Test("Classifies common extensions correctly")
    func classifyExtensions() {
        #expect(FileCategory.classify(path: "Assets.car") == .assetCatalog)
        #expect(FileCategory.classify(path: "Main.storyboardc") == .storyboard)
        #expect(FileCategory.classify(path: "icon.png") == .image)
        #expect(FileCategory.classify(path: "sound.mp3") == .audio)
        #expect(FileCategory.classify(path: "movie.mp4") == .video)
        #expect(FileCategory.classify(path: "font.ttf") == .font)
        #expect(FileCategory.classify(path: "Info.plist") == .plist)
        #expect(FileCategory.classify(path: "model.mlmodelc") == .mlModel)
        #expect(FileCategory.classify(path: "default.metallib") == .metalLibrary)
        #expect(FileCategory.classify(path: "lib.dylib") == .executable)
        #expect(FileCategory.classify(path: "Localizable.strings") == .strings)
    }

    @Test("Classifies code signature paths")
    func classifyCodeSignature() {
        #expect(FileCategory.classify(path: "_CodeSignature/CodeResources") == .codeSignature)
        #expect(FileCategory.classify(path: "Frameworks/Lib.framework/_CodeSignature/CodeResources") == .codeSignature)
    }

    @Test("Classifies framework paths")
    func classifyFramework() {
        #expect(FileCategory.classify(path: "Frameworks/Alamofire.framework/Alamofire") == .framework)
    }

    @Test("Classifies localization paths")
    func classifyLocalization() {
        #expect(FileCategory.classify(path: "en.lproj/Localizable.strings") == .localization)
        #expect(FileCategory.classify(path: "Base.lproj/Main.storyboardc") == .localization)
    }

    @Test("Unknown extensions classify as other")
    func classifyUnknown() {
        #expect(FileCategory.classify(path: "readme.txt") == .other)
        #expect(FileCategory.classify(path: "data.bin") == .other)
    }
}

@Suite("SizeFormatter Tests")
struct SizeFormatterTests {
    @Test("Formats byte sizes")
    func formatSizes() {
        #expect(SizeFormatter.format(0) == "0 B")
        #expect(SizeFormatter.format(512) == "512 B")
        #expect(SizeFormatter.format(1024) == "1.00 KB")
        #expect(SizeFormatter.format(1_048_576) == "1.00 MB")
        #expect(SizeFormatter.format(1_073_741_824) == "1.00 GB")
        #expect(SizeFormatter.format(13_000_000) == "12.4 MB")
    }

    @Test("Formats deltas with sign")
    func formatDeltas() {
        #expect(SizeFormatter.formatDelta(1024).hasPrefix("+"))
        #expect(SizeFormatter.formatDelta(-1024).hasPrefix("-"))
        #expect(SizeFormatter.formatDelta(0) == "+0 B")
    }

    @Test("Formats percentages")
    func formatPercentages() {
        #expect(SizeFormatter.formatPercentage(0.257) == "25.7%")
        #expect(SizeFormatter.formatPercentage(1.0) == "100.0%")
    }
}

@Suite("DuplicateDetector Tests")
struct DuplicateDetectorTests {
    @Test("Detects duplicate files by hash")
    func detectDuplicates() {
        let files = [
            FileEntry(relativePath: "a/icon.png", size: 1024, category: .image, contentHash: "abc123"),
            FileEntry(relativePath: "b/icon.png", size: 1024, category: .image, contentHash: "abc123"),
            FileEntry(relativePath: "c/icon.png", size: 1024, category: .image, contentHash: "abc123"),
            FileEntry(relativePath: "d/other.png", size: 2048, category: .image, contentHash: "def456"),
        ]

        let groups = DuplicateDetector.detect(files: files)
        #expect(groups.count == 1)
        #expect(groups[0].paths.count == 3)
        #expect(groups[0].wastedBytes == 2048)
        #expect(groups[0].duplicateCount == 2)
    }

    @Test("No duplicates when hashes differ")
    func noDuplicates() {
        let files = [
            FileEntry(relativePath: "a.png", size: 100, category: .image, contentHash: "aaa"),
            FileEntry(relativePath: "b.png", size: 200, category: .image, contentHash: "bbb"),
        ]

        let groups = DuplicateDetector.detect(files: files)
        #expect(groups.isEmpty)
    }

    @Test("Skips files without hashes")
    func skipsNilHashes() {
        let files = [
            FileEntry(relativePath: "MyApp", size: 5000, category: .executable, contentHash: nil),
            FileEntry(relativePath: "Other", size: 5000, category: .executable, contentHash: nil),
        ]

        let groups = DuplicateDetector.detect(files: files)
        #expect(groups.isEmpty)
    }
}

@Suite("MachOParser Tests")
struct MachOParserTests {
    @Test("Rejects non-Mach-O files")
    func rejectNonMachO() {
        let tempFile = NSTemporaryDirectory() + "not-macho-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: tempFile, contents: "hello".data(using: .utf8))
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        #expect(throws: MachOParser.ParseError.self) {
            try MachOParser.parse(path: tempFile)
        }
    }

    @Test("Parses a real system binary")
    func parseSystemBinary() throws {
        // /usr/lib/dyld is always present on macOS
        let info = try MachOParser.parse(path: "/usr/bin/true")
        #expect(!info.name.isEmpty)
        #expect(info.fileSize > 0)
        #expect(!info.slices.isEmpty)

        for slice in info.slices {
            #expect(!slice.architecture.isEmpty)
            #expect(!slice.segments.isEmpty)
        }
    }

    @Test("Parses dylib dependencies from system binary")
    func parseDylibDependencies() throws {
        let info = try MachOParser.parse(path: "/usr/bin/true")
        // /usr/bin/true links at least libSystem.B.dylib
        let allDeps = info.slices.flatMap(\.dependencies)
        #expect(!allDeps.isEmpty)
        #expect(allDeps.contains { $0.name.contains("libSystem") })
    }
}

@Suite("DylibVersion Tests")
struct DylibVersionTests {
    @Test("Decodes encoded version")
    func decodeVersion() {
        // 1.2.3 encoded as (1 << 16) | (2 << 8) | 3 = 0x00010203 = 66051
        let version = DylibVersion.from(encoded: 66051)
        #expect(version.major == 1)
        #expect(version.minor == 2)
        #expect(version.patch == 3)
        #expect(version.description == "1.2.3")
    }

    @Test("Decodes zero version")
    func decodeZero() {
        let version = DylibVersion.from(encoded: 0)
        #expect(version.major == 0)
        #expect(version.minor == 0)
        #expect(version.patch == 0)
    }

    @Test("Decodes large version numbers")
    func decodeLargeVersion() {
        // 88.1.0 = (88 << 16) | (1 << 8) | 0
        let encoded: UInt32 = (88 << 16) | (1 << 8)
        let version = DylibVersion.from(encoded: encoded)
        #expect(version.major == 88)
        #expect(version.minor == 1)
        #expect(version.patch == 0)
    }
}

@Suite("BudgetParser Tests")
struct BudgetParserTests {
    @Test("Parses MB values")
    func parseMB() throws {
        let bytes = try BudgetParser.parse("50MB").get()
        #expect(bytes == 50 * 1_048_576)
    }

    @Test("Parses GB values")
    func parseGB() throws {
        let bytes = try BudgetParser.parse("1.5GB").get()
        #expect(bytes == UInt64(1.5 * 1_073_741_824))
    }

    @Test("Parses KB values")
    func parseKB() throws {
        let bytes = try BudgetParser.parse("500KB").get()
        #expect(bytes == 500 * 1024)
    }

    @Test("Parses bare byte values")
    func parseBareBytes() throws {
        let bytes = try BudgetParser.parse("1048576").get()
        #expect(bytes == 1_048_576)
    }

    @Test("Case insensitive")
    func caseInsensitive() throws {
        let lower = try BudgetParser.parse("50mb").get()
        let upper = try BudgetParser.parse("50MB").get()
        #expect(lower == upper)
    }

    @Test("Rejects invalid input")
    func rejectInvalid() {
        let result = BudgetParser.parse("abc")
        switch result {
        case .success:
            Issue.record("Expected failure for invalid input")
        case .failure:
            break // expected
        }
    }

    @Test("Rejects empty input")
    func rejectEmpty() {
        let result = BudgetParser.parse("")
        switch result {
        case .success:
            Issue.record("Expected failure for empty input")
        case .failure:
            break // expected
        }
    }
}

@Suite("FileWalker Tests")
struct FileWalkerTests {
    @Test("Walks a temporary directory")
    func walkTempDir() throws {
        let tempDir = NSTemporaryDirectory() + "BundleProfilerTest-\(UUID().uuidString).app"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        // Create test files
        fm.createFile(atPath: tempDir + "/test.png", contents: Data(repeating: 0xAA, count: 1024))
        fm.createFile(atPath: tempDir + "/Info.plist", contents: Data(repeating: 0xBB, count: 256))

        let walker = FileWalker(bundlePath: tempDir)
        let files = try walker.walk()

        #expect(files.count == 2)
        #expect(files[0].size >= files[1].size) // sorted by size descending
        #expect(files.contains { $0.category == .image })
        #expect(files.contains { $0.category == .plist })
    }
}
