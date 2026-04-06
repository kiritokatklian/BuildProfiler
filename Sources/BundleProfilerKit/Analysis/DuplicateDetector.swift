//
//  DuplicateDetector.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Detects duplicate files by grouping entries with identical content hashes.
public struct DuplicateDetector: Sendable {
    /// Find duplicate groups from file entries, sorted by wasted bytes (descending).
    public static func detect(files: [FileEntry]) -> [DuplicateGroup] {
        // Group files by content hash (skip files without hashes)
        var hashGroups: [String: [(path: String, size: UInt64)]] = [:]

        for file in files {
            guard let hash = file.contentHash else { continue }
            hashGroups[hash, default: []].append((path: file.relativePath, size: file.size))
        }

        // Filter to groups with duplicates and create DuplicateGroup values
        return hashGroups.compactMap { hash, files in
            guard files.count > 1 else { return nil }

            return DuplicateGroup(
                contentHash: hash,
                fileSize: files[0].size,
                paths: files.map(\.path)
            )
        }
        .sorted { $0.wastedBytes > $1.wastedBytes }
    }
}
