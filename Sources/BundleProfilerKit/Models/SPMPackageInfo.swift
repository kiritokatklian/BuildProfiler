//
//  SPMPackageInfo.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Information about a detected Swift Package Manager dependency in the bundle.
public struct SPMPackageInfo: Codable, Sendable {
    /// Inferred package name.
    public let name: String

    /// Total size contributed by this package (framework + resource bundles + modules).
    public let totalSize: UInt64

    /// Dynamic framework associated with this package, if any.
    public let dynamicFramework: FrameworkInfo?

    /// Resource bundles following SPM naming convention (PackageName_TargetName.bundle).
    public let resourceBundles: [ResourceBundleInfo]

    /// Swift module files shipped in the bundle.
    public let swiftModules: [SwiftModuleInfo]

    public init(
        name: String,
        totalSize: UInt64,
        dynamicFramework: FrameworkInfo?,
        resourceBundles: [ResourceBundleInfo],
        swiftModules: [SwiftModuleInfo]
    ) {
        self.name = name
        self.totalSize = totalSize
        self.dynamicFramework = dynamicFramework
        self.resourceBundles = resourceBundles
        self.swiftModules = swiftModules
    }
}

/// A resource bundle shipped by an SPM package.
public struct ResourceBundleInfo: Codable, Sendable {
    /// Bundle display name.
    public let name: String

    /// Relative path within the app bundle.
    public let path: String

    /// Total size of the resource bundle.
    public let totalSize: UInt64

    /// Individual files inside the resource bundle.
    public let files: [FileEntry]

    public init(name: String, path: String, totalSize: UInt64, files: [FileEntry]) {
        self.name = name
        self.path = path
        self.totalSize = totalSize
        self.files = files
    }
}

/// A .swiftmodule file found in the bundle.
public struct SwiftModuleInfo: Codable, Sendable {
    /// Module name.
    public let moduleName: String

    /// Relative path within the app bundle.
    public let path: String

    /// Size in bytes.
    public let size: UInt64

    public init(moduleName: String, path: String, size: UInt64) {
        self.moduleName = moduleName
        self.path = path
        self.size = size
    }
}
