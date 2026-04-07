//
//  UnusedResource.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Report of potentially unused resources in the bundle.
public struct UnusedResourceReport: Codable, Sendable {
    /// Total number of resources scanned.
    public let totalResourcesScanned: Int

    /// Resources not found referenced in any binary.
    public let unusedResources: [UnusedResource]

    /// Known limitations of the detection algorithm.
    public let limitations: [String]

    /// Total bytes recoverable if all unused resources were removed.
    public var potentialSavings: UInt64 {
        unusedResources.reduce(0) { $0 + $1.fileSize }
    }

    public init(totalResourcesScanned: Int, unusedResources: [UnusedResource], limitations: [String]) {
        self.totalResourcesScanned = totalResourcesScanned
        self.unusedResources = unusedResources
        self.limitations = limitations
    }
}

/// A single resource that appears unused.
public struct UnusedResource: Codable, Sendable {
    /// Path relative to the bundle root.
    public let relativePath: String

    /// Size in bytes.
    public let fileSize: UInt64

    /// File category.
    public let category: FileCategory

    /// Resource names that were searched for in binaries.
    public let searchedNames: [String]

    public init(relativePath: String, fileSize: UInt64, category: FileCategory, searchedNames: [String]) {
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.category = category
        self.searchedNames = searchedNames
    }
}
