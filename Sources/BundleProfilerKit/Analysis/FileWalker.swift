//
//  FileWalker.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import CommonCrypto
import Foundation

/// Recursively enumerates files in a bundle, classifies them, and computes content hashes.
public struct FileWalker: Sendable {
    private let bundlePath: String
    private let skipHashing: Bool

    public init(bundlePath: String, skipHashing: Bool = false) {
        self.bundlePath = bundlePath
        self.skipHashing = skipHashing
    }

    /// Walk the bundle and return all file entries sorted by size (descending).
    public func walk() throws -> [FileEntry] {
        let fileManager = FileManager.default
        // Resolve symlinks so paths from enumerator match consistently
        let resolvedPath = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        let bundleURL = URL(fileURLWithPath: resolvedPath)

        guard let enumerator = fileManager.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [FileEntry] = []
        let pathPrefix = resolvedPath.hasSuffix("/") ? resolvedPath : resolvedPath + "/"

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])

            guard resourceValues.isRegularFile == true else { continue }

            let size = UInt64(resourceValues.fileSize ?? 0)
            let filePath = fileURL.standardizedFileURL.path
            let relativePath = filePath.hasPrefix(pathPrefix)
                ? String(filePath.dropFirst(pathPrefix.count))
                : filePath.replacingOccurrences(of: resolvedPath + "/", with: "")
            let category = FileCategory.classify(path: relativePath)

            let hash: String?
            if self.skipHashing || category == .executable {
                hash = nil
            } else {
                hash = try Self.sha256Hash(of: fileURL)
            }

            entries.append(FileEntry(
                relativePath: relativePath,
                size: size,
                category: category,
                contentHash: hash
            ))
        }

        return entries.sorted { $0.size > $1.size }
    }

    /// Compute SHA-256 hash of a file.
    private static func sha256Hash(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
