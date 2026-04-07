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
        var insights = [
            duplicateFiles(bundle),
            looseImages(bundle),
            smallFiles(bundle),
            unnecessaryFiles(bundle),
            largeImages(bundle),
            largeVideos(bundle),
            moduleMaps(bundle),
            stripDebugSymbols(bundle),
            unusedArchitectures(bundle),
            mainBinaryExports(bundle),
            imageOptimization(bundle),
            alternateIconOptimization(bundle),
            minifyStrings(bundle),
            spmResourceBundles(bundle),
        ]

        if let report = bundle.unusedResources {
            insights.append(unusedResourcesInsight(report, totalSize: bundle.totalSize))
        }

        if let report = bundle.extensionReport {
            insights.append(contentsOf: extensionInsights(report, totalSize: bundle.totalSize))
        }

        if let graph = bundle.dependencyGraph {
            insights.append(contentsOf: dependencyGraphInsights(graph, totalSize: bundle.totalSize))
        }

        return insights
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

    // MARK: - SPM Insights
    private static func spmResourceBundles(_ bundle: BundleInfo) -> Insight {
        let largeBundles = bundle.spmPackages.flatMap(\.resourceBundles).filter { $0.totalSize > 1_048_576 }
        let savings = largeBundles.reduce(UInt64(0)) { $0 + $1.totalSize }

        return Insight(
            id: "spm-resource-bundles",
            title: "Large SPM Resource Bundles",
            description: "SPM resource bundles over 1 MB may contain assets that could be optimized or loaded on demand.",
            severity: savings > 0 ? severity(for: savings, total: bundle.totalSize) : .passing,
            savingsBytes: savings,
            affectedFiles: largeBundles.map {
                InsightFile(path: $0.path, size: $0.totalSize, detail: "\($0.files.count) files")
            }
        )
    }

    // MARK: - Unused Resources Insight
    private static func unusedResourcesInsight(_ report: UnusedResourceReport, totalSize: UInt64) -> Insight {
        let savings = report.potentialSavings

        return Insight(
            id: "unused-resources",
            title: "Potentially Unused Resources",
            description: "Resources not referenced in any binary string table. Verify before removing — see limitations.",
            severity: report.unusedResources.isEmpty ? .passing : severity(for: savings, total: totalSize),
            savingsBytes: savings,
            affectedFiles: report.unusedResources.map {
                InsightFile(path: $0.relativePath, size: $0.fileSize, detail: "not found in any binary")
            }
        )
    }

    // MARK: - Extension Insights
    private static func extensionInsights(_ report: ExtensionOverheadReport, totalSize: UInt64) -> [Insight] {
        var insights: [Insight] = []

        // Duplicated frameworks across extensions
        if !report.duplicatedFrameworks.isEmpty {
            let savings = report.potentialSavings

            insights.append(Insight(
                id: "extension-duplicated-frameworks",
                title: "Duplicated Frameworks in Extensions",
                description: "Frameworks embedded in both the main app and extensions are shipped multiple times. Use app groups or framework sharing to deduplicate.",
                severity: severity(for: savings, total: totalSize),
                savingsBytes: savings,
                affectedFiles: report.duplicatedFrameworks.map {
                    InsightFile(
                        path: $0.name + ".framework",
                        size: $0.potentialSavings,
                        detail: $0.locations.joined(separator: ", ")
                    )
                }
            ))
        }

        return insights
    }

    // MARK: - Dependency Graph Insights
    private static func dependencyGraphInsights(_ graph: DependencyGraph, totalSize: UInt64) -> [Insight] {
        var insights: [Insight] = []

        // Redundant dependencies
        let redundant = graph.edges.filter(\.isRedundant)
        if !redundant.isEmpty {
            insights.append(Insight(
                id: "redundant-dependencies",
                title: "Redundant Dependency Links",
                description: "Some direct dependency links are redundant because the target is already reachable transitively. These don't add size but add launch-time overhead.",
                severity: .info,
                savingsBytes: 0,
                affectedFiles: redundant.map {
                    InsightFile(path: "\($0.from) -> \($0.to)", size: 0, detail: "redundant link")
                }
            ))
        }

        // Deep dependency chain contributing significant size
        let chainSize = graph.heaviestChain.totalSize
        if graph.heaviestChain.path.count > 2, chainSize > 0 {
            let chainPct = Double(chainSize) / Double(totalSize)
            if chainPct > 0.3 {
                insights.append(Insight(
                    id: "deep-dependency-chain",
                    title: "Heavy Dependency Chain",
                    description: "The heaviest dependency chain accounts for over 30% of binary size. Consider reducing transitive dependencies.",
                    severity: .warning,
                    savingsBytes: 0,
                    affectedFiles: graph.heaviestChain.path.compactMap { name in
                        guard let node = graph.nodes.first(where: { $0.name == name }),
                              !node.isSystemLibrary else { return nil }
                        return InsightFile(path: name, size: node.binarySize, detail: nil)
                    }
                ))
            }
        }

        // Weak-link candidates: large embedded frameworks that could be lazy-loaded
        let largeEmbedded = graph.nodes
            .filter { $0.nodeType == .embeddedFramework && $0.binarySize > 1_048_576 }
            .sorted { $0.binarySize > $1.binarySize }

        let weakLinked = Set(graph.edges.filter { $0.linkType == .weak || $0.linkType == .lazy }.map(\.to))
        let candidates = largeEmbedded.filter { !weakLinked.contains($0.name) }

        if !candidates.isEmpty {
            insights.append(Insight(
                id: "weak-link-candidates",
                title: "Weak-Link Candidates",
                description: "Large frameworks linked with LC_LOAD_DYLIB could potentially use weak or lazy linking to defer load-time cost if not always needed.",
                severity: .info,
                savingsBytes: 0,
                affectedFiles: candidates.prefix(10).map {
                    InsightFile(path: $0.name + ".framework", size: $0.binarySize, detail: "currently strong-linked")
                }
            ))
        }

        return insights
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
