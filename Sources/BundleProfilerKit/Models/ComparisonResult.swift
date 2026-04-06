//
//  ComparisonResult.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Result of comparing two bundles.
public struct ComparisonResult: Codable, Sendable {
    /// Name/path of the baseline bundle.
    public let baselineName: String

    /// Name/path of the current bundle.
    public let currentName: String

    /// Baseline total size.
    public let baselineSize: UInt64

    /// Current total size.
    public let currentSize: UInt64

    /// Size delta (positive = grew).
    public var sizeDelta: Int64 {
        Int64(currentSize) - Int64(baselineSize)
    }

    /// Per-category size deltas.
    public let categoryDeltas: [CategoryDelta]

    /// Per-framework size deltas.
    public let frameworkDeltas: [FrameworkDelta]

    /// Files added in the current bundle.
    public let addedFiles: [FileEntry]

    /// Files removed from the baseline bundle.
    public let removedFiles: [FileEntry]

    /// Files that changed size.
    public let changedFiles: [FileDelta]

    public init(
        baselineName: String,
        currentName: String,
        baselineSize: UInt64,
        currentSize: UInt64,
        categoryDeltas: [CategoryDelta],
        frameworkDeltas: [FrameworkDelta],
        addedFiles: [FileEntry],
        removedFiles: [FileEntry],
        changedFiles: [FileDelta]
    ) {
        self.baselineName = baselineName
        self.currentName = currentName
        self.baselineSize = baselineSize
        self.currentSize = currentSize
        self.categoryDeltas = categoryDeltas
        self.frameworkDeltas = frameworkDeltas
        self.addedFiles = addedFiles
        self.removedFiles = removedFiles
        self.changedFiles = changedFiles
    }
}

/// Size delta for a file category.
public struct CategoryDelta: Codable, Sendable {
    public let category: FileCategory
    public let baselineSize: UInt64
    public let currentSize: UInt64

    public var delta: Int64 {
        Int64(currentSize) - Int64(baselineSize)
    }

    public init(category: FileCategory, baselineSize: UInt64, currentSize: UInt64) {
        self.category = category
        self.baselineSize = baselineSize
        self.currentSize = currentSize
    }
}

/// Size delta for a framework.
public struct FrameworkDelta: Codable, Sendable {
    public let name: String
    public let baselineSize: UInt64
    public let currentSize: UInt64

    public var delta: Int64 {
        Int64(currentSize) - Int64(baselineSize)
    }

    public init(name: String, baselineSize: UInt64, currentSize: UInt64) {
        self.name = name
        self.baselineSize = baselineSize
        self.currentSize = currentSize
    }
}

/// Size delta for a specific file.
public struct FileDelta: Codable, Sendable {
    public let relativePath: String
    public let baselineSize: UInt64
    public let currentSize: UInt64

    public var delta: Int64 {
        Int64(currentSize) - Int64(baselineSize)
    }

    public init(relativePath: String, baselineSize: UInt64, currentSize: UInt64) {
        self.relativePath = relativePath
        self.baselineSize = baselineSize
        self.currentSize = currentSize
    }
}
