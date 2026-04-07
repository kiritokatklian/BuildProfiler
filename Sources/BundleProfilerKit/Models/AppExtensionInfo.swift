//
//  AppExtensionInfo.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Analysis of a single .appex bundle.
public struct AppExtensionInfo: Codable, Sendable {
    /// Extension display name.
    public let name: String

    /// Relative path within the app bundle.
    public let path: String

    /// Total size of the .appex directory.
    public let totalSize: UInt64

    /// Size of the extension's main executable.
    public let executableSize: UInt64

    /// Size breakdown by file category.
    public let categoryBreakdown: [FileCategory: UInt64]

    /// Frameworks embedded in this extension.
    public let frameworks: [FrameworkInfo]

    public init(
        name: String,
        path: String,
        totalSize: UInt64,
        executableSize: UInt64,
        categoryBreakdown: [FileCategory: UInt64],
        frameworks: [FrameworkInfo]
    ) {
        self.name = name
        self.path = path
        self.totalSize = totalSize
        self.executableSize = executableSize
        self.categoryBreakdown = categoryBreakdown
        self.frameworks = frameworks
    }
}

/// Report of overhead introduced by app extensions.
public struct ExtensionOverheadReport: Codable, Sendable {
    /// All analyzed extensions.
    public let extensions: [AppExtensionInfo]

    /// Total size of all extensions combined.
    public let totalExtensionSize: UInt64

    /// Frameworks duplicated between the main app and/or extensions.
    public let duplicatedFrameworks: [DuplicatedFramework]

    /// Bytes recoverable by deduplicating frameworks.
    public let potentialSavings: UInt64

    public init(
        extensions: [AppExtensionInfo],
        totalExtensionSize: UInt64,
        duplicatedFrameworks: [DuplicatedFramework],
        potentialSavings: UInt64
    ) {
        self.extensions = extensions
        self.totalExtensionSize = totalExtensionSize
        self.duplicatedFrameworks = duplicatedFrameworks
        self.potentialSavings = potentialSavings
    }
}

/// A framework that appears in multiple locations (main app and/or extensions).
public struct DuplicatedFramework: Codable, Sendable {
    /// Framework name.
    public let name: String

    /// Size of a single copy.
    public let sizePerCopy: UInt64

    /// Where this framework appears (e.g., ["main", "WidgetExtension"]).
    public let locations: [String]

    /// Bytes wasted: sizePerCopy * (copies - 1).
    public let potentialSavings: UInt64

    public init(name: String, sizePerCopy: UInt64, locations: [String], potentialSavings: UInt64) {
        self.name = name
        self.sizePerCopy = sizePerCopy
        self.locations = locations
        self.potentialSavings = potentialSavings
    }
}
