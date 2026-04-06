//
//  FileEntry.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// A single file within the bundle with its size, category, and content hash.
public struct FileEntry: Codable, Sendable {
    /// Path relative to the bundle root.
    public let relativePath: String

    /// Size in bytes on disk.
    public let size: UInt64

    /// Classified category based on extension/path.
    public let category: FileCategory

    /// SHA-256 content hash (hex string). Nil for executables (skipped for performance).
    public let contentHash: String?

    public init(relativePath: String, size: UInt64, category: FileCategory, contentHash: String?) {
        self.relativePath = relativePath
        self.size = size
        self.category = category
        self.contentHash = contentHash
    }
}
