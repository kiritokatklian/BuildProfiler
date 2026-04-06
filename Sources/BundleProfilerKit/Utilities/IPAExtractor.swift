//
//  IPAExtractor.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Extracts an .ipa file to a temporary directory and locates the .app bundle within.
public enum IPAExtractor: Sendable {
    public enum ExtractionError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case extractionFailed(String)
        case appNotFound(String)

        public var description: String {
            switch self {
            case .fileNotFound(let path):
                "IPA file not found: \(path)"
            case .extractionFailed(let reason):
                "Failed to extract IPA: \(reason)"
            case .appNotFound(let path):
                "No .app bundle found in extracted IPA: \(path)"
            }
        }
    }

    /// Extract an .ipa to a temporary directory and return the path to the .app bundle.
    ///
    /// The caller is responsible for cleaning up the returned temporary directory's parent.
    /// Use `cleanUp(tempDirectory:)` when done.
    public static func extract(ipaPath: String) throws -> (appPath: String, tempDirectory: String) {
        #if os(macOS)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: ipaPath) else {
            throw ExtractionError.fileNotFound(ipaPath)
        }

        let tempDir = NSTemporaryDirectory() + "BundleProfiler-\(UUID().uuidString)"
        try fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", ipaPath, "-d", tempDir]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExtractionError.extractionFailed("unzip exited with status \(process.terminationStatus)")
        }

        // Look for .app inside Payload/
        let payloadDir = tempDir + "/Payload"
        if fileManager.fileExists(atPath: payloadDir) {
            let contents = try fileManager.contentsOfDirectory(atPath: payloadDir)
            if let appDir = contents.first(where: { $0.hasSuffix(".app") }) {
                return (appPath: payloadDir + "/" + appDir, tempDirectory: tempDir)
            }
        }

        // Fallback: search recursively for .app
        if let enumerator = fileManager.enumerator(atPath: tempDir) {
            while let path = enumerator.nextObject() as? String {
                if path.hasSuffix(".app"), !path.contains(".app/") {
                    return (appPath: tempDir + "/" + path, tempDirectory: tempDir)
                }
            }
        }

        throw ExtractionError.appNotFound(tempDir)
        #else
        throw ExtractionError.extractionFailed("IPA extraction is only supported on macOS")
        #endif
    }

    /// Remove the temporary directory created during extraction.
    public static func cleanUp(tempDirectory: String) {
        try? FileManager.default.removeItem(atPath: tempDirectory)
    }
}
