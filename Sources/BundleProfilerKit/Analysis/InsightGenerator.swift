//
//  InsightGenerator.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Analyzes a `BundleInfo` and produces actionable optimization insights.
public struct InsightGenerator: Sendable {
    /// Generate all insights for the given bundle.
    public static func generate(from bundle: BundleInfo) -> [Insight] {
        [
            duplicateFiles(bundle),
            looseImages(bundle),
            smallFiles(bundle),
            unnecessaryFiles(bundle),
            largeImages(bundle),
            largeVideos(bundle),
            headerFiles(bundle),
            moduleMaps(bundle),
            stripDebugSymbols(bundle),
            unusedArchitectures(bundle),
            mainBinaryExports(bundle),
            imageOptimization(bundle),
            alternateIconOptimization(bundle),
            minifyStrings(bundle),
        ]
    }

    // MARK: - BundleInfo-Based Insights
    private static func duplicateFiles(_ bundle: BundleInfo) -> Insight {
        let groups = bundle.duplicates.filter { $0.paths.count >= 2 }
        let savings = bundle.totalWastedBytes
        let files = groups.flatMap { group in
            group.paths.map { path in
                InsightFile(
                    path: path,
                    size: group.fileSize,
                    detail: "\(group.paths.count) copies"
                )
            }
        }

        return Insight(
            id: "duplicate-files",
            title: "Duplicate Files",
            description: "Multiple files share identical content. Deduplicate by referencing a single copy or using asset catalogs.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: files
        )
    }

    private static func looseImages(_ bundle: BundleInfo) -> Insight {
        let matched = bundle.files.filter { file in
            file.category == .image
            && !file.relativePath.contains(".car")
            && (file.relativePath.contains("@1x") || file.relativePath.contains("@2x") || file.relativePath.contains("@3x"))
        }
        let savings = matched.reduce(UInt64(0)) { $0 + $1.size }

        return Insight(
            id: "loose-images",
            title: "Loose Images",
            description: "Scale-variant images outside asset catalogs prevent app thinning. Move them into an asset catalog so only the device-appropriate scale ships.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map { file in
                let scale = file.relativePath.contains("@3x") ? "@3x" : file.relativePath.contains("@2x") ? "@2x" : "@1x"
                return InsightFile(path: file.relativePath, size: file.size, detail: "\(scale) outside catalog")
            }
        )
    }

    private static func smallFiles(_ bundle: BundleInfo) -> Insight {
        let threshold: UInt64 = 4096
        let matched = bundle.files.filter { $0.size < threshold && $0.size > 0 }
        let savings = matched.reduce(UInt64(0)) { $0 + (threshold - $1.size) }

        return Insight(
            id: "small-files",
            title: "Small Files",
            description: "Files smaller than 4 KB still occupy a full filesystem block. Consolidating them reduces block-padding waste.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map {
                InsightFile(path: $0.relativePath, size: $0.size, detail: "\(threshold - $0.size) B padding")
            }
        )
    }

    private static func unnecessaryFiles(_ bundle: BundleInfo) -> Insight {
        let junkExtensions: Set<String> = [
            "md", "txt", "sh", "py", "rb", "yml", "yaml",
            "gitignore", "gitkeep", "DS_Store", "lock",
        ]
        let junkFilenames: Set<String> = [
            "README", "LICENSE", "CHANGELOG", "Makefile",
            "Podfile", "Cartfile", "Package.swift", ".swiftlint.yml",
        ]

        let matched = bundle.files.filter { file in
            let ext = (file.relativePath as NSString).pathExtension.lowercased()
            let filename = (file.relativePath as NSString).lastPathComponent
            return junkExtensions.contains(ext) || junkFilenames.contains(filename)
        }
        let savings = matched.reduce(UInt64(0)) { $0 + $1.size }

        return Insight(
            id: "unnecessary-files",
            title: "Unnecessary Files",
            description: "Build artifacts, documentation, and config files that serve no purpose at runtime. Exclude them from the bundle via build settings.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map {
                InsightFile(path: $0.relativePath, size: $0.size, detail: nil)
            }
        )
    }

    private static func largeImages(_ bundle: BundleInfo) -> Insight {
        let threshold: UInt64 = 10_485_760
        let matched = bundle.files.filter { $0.category == .image && $0.size > threshold }
        let savings = matched.reduce(UInt64(0)) { $0 + ($1.size - threshold) }

        return Insight(
            id: "large-images",
            title: "Large Images",
            description: "Images over 10 MB are unusually large for mobile. Consider downscaling, compressing, or loading them on demand from a server.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map {
                InsightFile(path: $0.relativePath, size: $0.size, detail: nil)
            }
        )
    }

    private static func largeVideos(_ bundle: BundleInfo) -> Insight {
        let threshold: UInt64 = 10_485_760
        let matched = bundle.files.filter { $0.category == .video && $0.size > threshold }
        let savings = matched.reduce(UInt64(0)) { $0 + ($1.size - threshold) }

        return Insight(
            id: "large-videos",
            title: "Large Videos",
            description: "Videos over 10 MB increase download size significantly. Stream them from a CDN or use more aggressive compression (HEVC).",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map {
                InsightFile(path: $0.relativePath, size: $0.size, detail: nil)
            }
        )
    }

    private static func headerFiles(_ bundle: BundleInfo) -> Insight {
        let matched = bundle.files.filter { $0.category == .header }
        let savings = matched.reduce(UInt64(0)) { $0 + $1.size }

        return Insight(
            id: "header-files",
            title: "Header Files",
            description: "C/ObjC headers are only needed at compile time. Strip them from release builds with COPY_HEADERS_RUN_UNIFDEF or custom build phases.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map {
                InsightFile(path: $0.relativePath, size: $0.size, detail: nil)
            }
        )
    }

    private static func moduleMaps(_ bundle: BundleInfo) -> Insight {
        let matched = bundle.files.filter { $0.category == .moduleMap }
        let savings = matched.reduce(UInt64(0)) { $0 + $1.size }

        return Insight(
            id: "module-maps",
            title: "Module Maps",
            description: "Module maps are needed by the compiler, not at runtime. Remove them from the bundle in release builds.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map {
                InsightFile(path: $0.relativePath, size: $0.size, detail: nil)
            }
        )
    }

    // MARK: - MachO-Based Insights
    private static func allMachOInfos(_ bundle: BundleInfo) -> [MachOInfo] {
        var infos: [MachOInfo] = []
        if let main = bundle.mainExecutable {
            infos.append(main)
        }
        for fw in bundle.frameworks {
            if let machO = fw.machOInfo {
                infos.append(machO)
            }
        }
        return infos
    }

    private static func stripDebugSymbols(_ bundle: BundleInfo) -> Insight {
        var files: [InsightFile] = []
        var savings: UInt64 = 0

        for machO in allMachOInfos(bundle) {
            for slice in machO.slices {
                for segment in slice.segments where segment.name == "__DWARF" {
                    savings += segment.fileSize
                    files.append(InsightFile(
                        path: machO.name,
                        size: segment.fileSize,
                        detail: "\(slice.architecture) __DWARF segment"
                    ))
                }
            }
        }

        return Insight(
            id: "strip-debug-symbols",
            title: "Strip Debug Symbols",
            description: "One or more binaries contain __DWARF debug info. Set STRIP_INSTALLED_PRODUCT = YES and DEBUG_INFORMATION_FORMAT = dwarf-with-dsym for release builds.",
            severity: files.isEmpty ? .passing : .critical,
            savingsBytes: savings,
            affectedFiles: files
        )
    }

    private static func unusedArchitectures(_ bundle: BundleInfo) -> Insight {
        var files: [InsightFile] = []
        var savings: UInt64 = 0

        for machO in allMachOInfos(bundle) {
            for slice in machO.slices where slice.architecture != "arm64" {
                savings += slice.size
                files.append(InsightFile(
                    path: machO.name,
                    size: slice.size,
                    detail: "\(slice.architecture) slice"
                ))
            }
        }

        return Insight(
            id: "unused-architectures",
            title: "Unused Architectures",
            description: "Non-arm64 slices are unnecessary for App Store and TestFlight. Ensure ARCHS is set to arm64 only for release builds, or use a post-build strip phase.",
            severity: files.isEmpty ? .passing : .critical,
            savingsBytes: savings,
            affectedFiles: files
        )
    }

    private static func mainBinaryExports(_ bundle: BundleInfo) -> Insight {
        guard let main = bundle.mainExecutable else {
            return Insight(
                id: "main-binary-exports",
                title: "Main Binary Export Trie",
                description: "The main executable's export trie is unnecessary for a non-library binary. Use -exported_symbols_list with an empty file to strip it.",
                severity: .passing,
                savingsBytes: 0,
                affectedFiles: []
            )
        }

        var savings: UInt64 = 0
        var files: [InsightFile] = []

        for slice in main.slices {
            if let linkedit = slice.segments.first(where: { $0.name == "__LINKEDIT" }) {
                let estimated = linkedit.fileSize * 2 / 100
                savings += estimated
                files.append(InsightFile(
                    path: main.name,
                    size: estimated,
                    detail: "\(slice.architecture) ~2% of __LINKEDIT"
                ))
            }
        }

        return Insight(
            id: "main-binary-exports",
            title: "Main Binary Export Trie",
            description: "The main executable's export trie is unnecessary for a non-library binary. Use -exported_symbols_list with an empty file to strip it.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: files
        )
    }

    // MARK: - Heuristic Insights
    private static func imageOptimization(_ bundle: BundleInfo) -> Insight {
        let compressibleExtensions: Set<String> = ["png", "jpeg", "jpg", "tiff", "tif", "bmp"]
        let threshold: UInt64 = 102_400

        let matched = bundle.files.filter { file in
            guard file.category == .image, file.size > threshold else { return false }
            let ext = (file.relativePath as NSString).pathExtension.lowercased()
            return compressibleExtensions.contains(ext)
        }
        let totalSize = matched.reduce(UInt64(0)) { $0 + $1.size }
        let savings = totalSize * 30 / 100

        return Insight(
            id: "image-optimization",
            title: "Image Optimization",
            description: "Large PNG/JPEG/TIFF/BMP images can typically be compressed 30%+ by converting to HEIC/WebP or using lossy re-encoding.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map {
                let ext = ($0.relativePath as NSString).pathExtension.lowercased()
                return InsightFile(path: $0.relativePath, size: $0.size, detail: "\(ext) > 100 KB")
            }
        )
    }

    private static func alternateIconOptimization(_ bundle: BundleInfo) -> Insight {
        let threshold: UInt64 = 50_000
        var files: [InsightFile] = []
        var totalSize: UInt64 = 0

        for catalog in bundle.assetCatalogs {
            for asset in catalog.assets {
                let size = asset.size ?? 0
                guard size > threshold else { continue }
                let name = asset.name.lowercased()
                guard name.contains("appicon") else { continue }
                // Exclude the primary AppIcon (exact match, case-insensitive)
                guard asset.name.lowercased() != "appicon" else { continue }

                totalSize += size
                files.append(InsightFile(
                    path: "\(catalog.path)/\(asset.name)",
                    size: size,
                    detail: "alternate icon"
                ))
            }
        }

        let savings = totalSize * 80 / 100

        return Insight(
            id: "alternate-icon-optimization",
            title: "Alternate App Icon Optimization",
            description: "Alternate app icons only need 180×180 pixels but are often stored at 1024×1024. Resize them to the required dimensions.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: files
        )
    }

    private static func minifyStrings(_ bundle: BundleInfo) -> Insight {
        let matched = bundle.files.filter { $0.category == .strings && $0.size > 0 }
        let totalSize = matched.reduce(UInt64(0)) { $0 + $1.size }
        let savings = totalSize * 15 / 100

        return Insight(
            id: "minify-strings",
            title: "Minify Localized Strings",
            description: "Xcode strings files often include comments and verbose encodings. Stripping comments and converting to binary plists can reduce their size.",
            severity: severity(for: savings, total: bundle.totalSize),
            savingsBytes: savings,
            affectedFiles: matched.map {
                InsightFile(path: $0.relativePath, size: $0.size, detail: nil)
            }
        )
    }

    // MARK: - Severity Helpers
    private static func severity(for savings: UInt64, total: UInt64) -> InsightSeverity {
        guard savings > 0, total > 0 else { return .passing }
        let percentage = Double(savings) / Double(total) * 100
        if percentage > 5 { return .critical }
        if percentage > 1 { return .warning }
        return .info
    }
}
