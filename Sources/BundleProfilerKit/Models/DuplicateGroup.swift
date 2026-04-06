//
//  DuplicateGroup.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//
import Foundation

/// A group of files sharing identical content (same SHA-256 hash).
public struct DuplicateGroup: Codable, Sendable {
    /// SHA-256 hash shared by all files in the group.
    public let contentHash: String

    /// Size of each individual file.
    public let fileSize: UInt64

    /// Relative paths of all duplicate files.
    public let paths: [String]

    /// Number of duplicate copies (paths.count - 1).
    public var duplicateCount: Int {
        paths.count - 1
    }

    /// Total bytes wasted by duplicates.
    public var wastedBytes: UInt64 {
        fileSize * UInt64(duplicateCount)
    }

    public init(contentHash: String, fileSize: UInt64, paths: [String]) {
        self.contentHash = contentHash
        self.fileSize = fileSize
        self.paths = paths
    }
}
