//
//  UnusedResourceDetector.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Detects resources that may be unused by comparing resource names against strings in binaries.
public struct UnusedResourceDetector: Sendable {
    /// Categories of files considered scannable resources.
    private static let resourceCategories: Set<FileCategory> = [
        .image, .font, .audio, .video, .mlModel, .strings,
    ]

    /// File/directory patterns to always exclude from unused detection.
    private static let excludedPrefixes = [
        "AppIcon", "LaunchImage", "Default",
    ]

    /// Known limitations of this detection approach.
    private static let knownLimitations = [
        "Compiled storyboard/XIB references cannot be parsed — resources referenced only from Interface Builder may appear as unused",
        "Dynamically constructed resource names (e.g., \"icon_\\(index)\") cannot be detected",
        "Resources loaded via server-provided keys or user defaults are not detectable",
        "Asset catalog savings are estimates — actual .car size may not shrink proportionally",
    ]

    /// Detect potentially unused resources in the bundle.
    ///
    /// - Parameters:
    ///   - files: All files in the bundle.
    ///   - assetCatalogs: Parsed asset catalog info.
    ///   - mainExecutablePath: Full path to the main executable binary.
    ///   - mainExecutableMachO: Parsed MachO info for the main executable.
    ///   - frameworkBinaries: Array of (path, machOInfo) for framework binaries.
    /// - Returns: Report of unused resources.
    public static func detect(
        files: [FileEntry],
        assetCatalogs: [AssetCatalogInfo],
        mainExecutablePath: String?,
        mainExecutableMachO: MachOInfo?,
        frameworkBinaries: [(path: String, machO: MachOInfo)]
    ) -> UnusedResourceReport {
        // Step 1: Build string corpus from all binaries
        var stringCorpus: Set<String> = []

        if let path = mainExecutablePath, let machO = mainExecutableMachO {
            stringCorpus.formUnion(MachOStringExtractor.extractStrings(binaryPath: path, machOInfo: machO))
        }

        for (path, machO) in frameworkBinaries {
            stringCorpus.formUnion(MachOStringExtractor.extractStrings(binaryPath: path, machOInfo: machO))
        }

        // Also build a lowercased corpus for case-insensitive fallback
        let lowercasedCorpus = Set(stringCorpus.map { $0.lowercased() })

        // Step 2: Identify candidate resources
        var candidates: [(relativePath: String, fileSize: UInt64, category: FileCategory, searchNames: [String])] = []

        // Files on disk
        for file in files {
            guard Self.resourceCategories.contains(file.category) else { continue }
            guard !shouldExclude(path: file.relativePath) else { continue }

            let names = generateSearchNames(for: file.relativePath)
            candidates.append((file.relativePath, file.size, file.category, names))
        }

        // Individual assets from asset catalogs
        for catalog in assetCatalogs {
            for asset in catalog.assets {
                let assetName = asset.name
                guard !Self.excludedPrefixes.contains(where: { assetName.hasPrefix($0) }) else { continue }
                let names = [assetName, assetName.lowercased()]
                let size = asset.size ?? 0
                candidates.append(("\(catalog.path)/\(assetName)", size, .assetCatalog, names))
            }
        }

        let totalScanned = candidates.count

        // Step 3: Match against string corpus
        var unused: [UnusedResource] = []

        for candidate in candidates {
            let isReferenced = candidate.searchNames.contains { name in
                // Exact match first
                if stringCorpus.contains(name) { return true }
                // Case-insensitive exact match
                if lowercasedCorpus.contains(name.lowercased()) { return true }
                // Substring scan as fallback (expensive, but catches partial matches)
                return stringCorpus.contains { $0.contains(name) }
            }

            if !isReferenced {
                unused.append(UnusedResource(
                    relativePath: candidate.relativePath,
                    fileSize: candidate.fileSize,
                    category: candidate.category,
                    searchedNames: candidate.searchNames
                ))
            }
        }

        unused.sort { $0.fileSize > $1.fileSize }

        return UnusedResourceReport(
            totalResourcesScanned: totalScanned,
            unusedResources: unused,
            limitations: Self.knownLimitations
        )
    }

    // MARK: - Helpers
    /// Generate search name variants for a resource path.
    private static func generateSearchNames(for relativePath: String) -> [String] {
        let filename = (relativePath as NSString).lastPathComponent
        let nameWithoutExt = (filename as NSString).deletingPathExtension

        var names: Set<String> = [filename, nameWithoutExt]

        // Strip scale suffixes: icon@2x -> icon
        let scalePattern = ["@1x", "@2x", "@3x"]
        for suffix in scalePattern {
            if nameWithoutExt.hasSuffix(suffix) {
                let stripped = String(nameWithoutExt.dropLast(suffix.count))
                if !stripped.isEmpty {
                    names.insert(stripped)
                }
            }
        }

        // Strip ~iphone/~ipad suffixes
        for suffix in ["~iphone", "~ipad"] {
            if nameWithoutExt.hasSuffix(suffix) {
                let stripped = String(nameWithoutExt.dropLast(suffix.count))
                if !stripped.isEmpty {
                    names.insert(stripped)
                }
            }
        }

        return Array(names)
    }

    /// Determine if a resource path should be excluded from unused detection.
    private static func shouldExclude(path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent

        // Exclude system-required resources
        for prefix in Self.excludedPrefixes {
            if filename.hasPrefix(prefix) { return true }
        }

        // Exclude code signatures and lproj directories
        if path.contains("_CodeSignature/") { return true }
        if path.contains(".lproj/") { return true }

        // Exclude Info.plist referenced resources
        if filename == "Info.plist" { return true }

        return false
    }
}
