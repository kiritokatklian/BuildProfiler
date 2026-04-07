//
//  BundleInfo.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Top-level result of analyzing an app bundle.
public struct BundleInfo: Codable, Sendable {
    /// Name of the bundle (e.g., "MyApp.app").
    public let bundleName: String

    /// Total bundle size in bytes.
    public let totalSize: UInt64

    /// All files in the bundle.
    public let files: [FileEntry]

    /// Size breakdown by category.
    public let categoryBreakdown: [FileCategory: UInt64]

    /// Mach-O analysis of the main executable.
    public let mainExecutable: MachOInfo?

    /// Per-framework breakdown.
    public let frameworks: [FrameworkInfo]

    /// Duplicate resource groups.
    public let duplicates: [DuplicateGroup]

    /// Asset catalog analysis results.
    public let assetCatalogs: [AssetCatalogInfo]

    /// Detected Swift Package Manager dependencies.
    public let spmPackages: [SPMPackageInfo]

    /// Report of potentially unused resources (opt-in via `--unused-resources`).
    public let unusedResources: UnusedResourceReport?

    /// App extension overhead analysis.
    public let extensionReport: ExtensionOverheadReport?

    /// Binary dependency graph.
    public let dependencyGraph: DependencyGraph?

    /// Total wasted bytes from duplicates.
    public var totalWastedBytes: UInt64 {
        duplicates.reduce(0) { $0 + $1.wastedBytes }
    }

    public init(
        bundleName: String,
        totalSize: UInt64,
        files: [FileEntry],
        categoryBreakdown: [FileCategory: UInt64],
        mainExecutable: MachOInfo?,
        frameworks: [FrameworkInfo],
        duplicates: [DuplicateGroup],
        assetCatalogs: [AssetCatalogInfo],
        spmPackages: [SPMPackageInfo] = [],
        unusedResources: UnusedResourceReport? = nil,
        extensionReport: ExtensionOverheadReport? = nil,
        dependencyGraph: DependencyGraph? = nil
    ) {
        self.bundleName = bundleName
        self.totalSize = totalSize
        self.files = files
        self.categoryBreakdown = categoryBreakdown
        self.mainExecutable = mainExecutable
        self.frameworks = frameworks
        self.duplicates = duplicates
        self.assetCatalogs = assetCatalogs
        self.spmPackages = spmPackages
        self.unusedResources = unusedResources
        self.extensionReport = extensionReport
        self.dependencyGraph = dependencyGraph
    }
}

/// Information about an asset catalog (.car file).
public struct AssetCatalogInfo: Codable, Sendable {
    /// Relative path to the .car file.
    public let path: String

    /// File size on disk.
    public let fileSize: UInt64

    /// Number of assets in the catalog.
    public let assetCount: Int

    /// Individual asset entries, if available.
    public let assets: [AssetEntry]

    public init(path: String, fileSize: UInt64, assetCount: Int, assets: [AssetEntry]) {
        self.path = path
        self.fileSize = fileSize
        self.assetCount = assetCount
        self.assets = assets
    }
}

/// A single asset within an asset catalog.
public struct AssetEntry: Codable, Sendable {
    public let name: String
    public let renditionName: String?
    public let size: UInt64?

    public init(name: String, renditionName: String?, size: UInt64?) {
        self.name = name
        self.renditionName = renditionName
        self.size = size
    }
}
