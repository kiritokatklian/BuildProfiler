//
//  AppExtensionAnalyzer.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Analyzes app extension (.appex) bundles and detects framework duplication.
public struct AppExtensionAnalyzer: Sendable {
    /// Analyze all app extensions and compute overhead from duplicated frameworks.
    ///
    /// - Parameters:
    ///   - bundlePath: Full path to the .app bundle.
    ///   - mainFrameworks: Frameworks already analyzed from the main app.
    ///   - analyzeMachO: Whether to perform Mach-O analysis on extension binaries.
    /// - Returns: Report, or nil if no extensions exist.
    public static func analyze(
        bundlePath: String,
        mainFrameworks: [FrameworkInfo],
        analyzeMachO: Bool
    ) -> ExtensionOverheadReport? {
        let fileManager = FileManager.default
        let plugInsDir = bundlePath + "/PlugIns"

        guard fileManager.fileExists(atPath: plugInsDir),
              let contents = try? fileManager.contentsOfDirectory(atPath: plugInsDir)
        else {
            return nil
        }

        let appexDirs = contents.filter { $0.hasSuffix(".appex") }
        guard !appexDirs.isEmpty else { return nil }

        // Analyze each extension
        var extensions: [AppExtensionInfo] = []

        for appexDir in appexDirs {
            let appexPath = plugInsDir + "/" + appexDir
            let extName = (appexDir as NSString).deletingPathExtension

            guard let extInfo = analyzeExtension(
                name: extName,
                appexPath: appexPath,
                relativePath: "PlugIns/" + appexDir,
                analyzeMachO: analyzeMachO
            ) else {
                continue
            }

            extensions.append(extInfo)
        }

        guard !extensions.isEmpty else { return nil }

        let totalExtensionSize = extensions.reduce(UInt64(0)) { $0 + $1.totalSize }

        // Detect duplicated frameworks across main app and all extensions
        let duplicated = detectDuplicatedFrameworks(
            mainFrameworks: mainFrameworks,
            extensions: extensions
        )

        let potentialSavings = duplicated.reduce(UInt64(0)) { $0 + $1.potentialSavings }

        return ExtensionOverheadReport(
            extensions: extensions.sorted { $0.totalSize > $1.totalSize },
            totalExtensionSize: totalExtensionSize,
            duplicatedFrameworks: duplicated.sorted { $0.potentialSavings > $1.potentialSavings },
            potentialSavings: potentialSavings
        )
    }

    // MARK: - Single Extension Analysis
    private static func analyzeExtension(
        name: String,
        appexPath: String,
        relativePath: String,
        analyzeMachO: Bool
    ) -> AppExtensionInfo? {
        let walker = FileWalker(bundlePath: appexPath, skipHashing: true)
        guard let files = try? walker.walk() else { return nil }

        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }

        // Category breakdown
        var categoryBreakdown: [FileCategory: UInt64] = [:]
        for file in files {
            categoryBreakdown[file.category, default: 0] += file.size
        }

        // Find executable size
        let execPath = appexPath + "/" + name
        let executableSize: UInt64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: execPath),
           let size = attrs[.size] as? UInt64
        {
            executableSize = size
        } else {
            executableSize = 0
        }

        // Analyze embedded frameworks
        let frameworks = analyzeExtensionFrameworks(
            appexPath: appexPath,
            files: files,
            analyzeMachO: analyzeMachO
        )

        return AppExtensionInfo(
            name: name,
            path: relativePath,
            totalSize: totalSize,
            executableSize: executableSize,
            categoryBreakdown: categoryBreakdown,
            frameworks: frameworks
        )
    }

    private static func analyzeExtensionFrameworks(
        appexPath: String,
        files: [FileEntry],
        analyzeMachO: Bool
    ) -> [FrameworkInfo] {
        let frameworksDir = appexPath + "/Frameworks"
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: frameworksDir),
              let contents = try? fileManager.contentsOfDirectory(atPath: frameworksDir)
        else {
            return []
        }

        return contents
            .filter { $0.hasSuffix(".framework") }
            .compactMap { frameworkDir -> FrameworkInfo? in
                let frameworkPath = frameworksDir + "/" + frameworkDir
                let name = (frameworkDir as NSString).deletingPathExtension

                let prefix = "Frameworks/" + frameworkDir + "/"
                let frameworkFiles = files.filter { $0.relativePath.hasPrefix(prefix) }
                let totalSize = frameworkFiles.reduce(UInt64(0)) { $0 + $1.size }

                let binaryPath = frameworkPath + "/" + name
                let binarySize: UInt64
                if let attrs = try? fileManager.attributesOfItem(atPath: binaryPath),
                   let size = attrs[.size] as? UInt64
                {
                    binarySize = size
                } else {
                    binarySize = 0
                }

                let codeSignatureSize = frameworkFiles
                    .filter { $0.category == .codeSignature }
                    .reduce(UInt64(0)) { $0 + $1.size }

                let resourceSize = totalSize >= (binarySize + codeSignatureSize)
                    ? totalSize - binarySize - codeSignatureSize
                    : 0

                let machOInfo: MachOInfo?
                if analyzeMachO, binarySize > 0 {
                    machOInfo = try? MachOParser.parse(path: binaryPath)
                } else {
                    machOInfo = nil
                }

                return FrameworkInfo(
                    name: name,
                    totalSize: totalSize,
                    binarySize: binarySize,
                    resourceSize: resourceSize,
                    codeSignatureSize: codeSignatureSize,
                    machOInfo: machOInfo
                )
            }
            .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Duplicated Framework Detection
    private static func detectDuplicatedFrameworks(
        mainFrameworks: [FrameworkInfo],
        extensions: [AppExtensionInfo]
    ) -> [DuplicatedFramework] {
        // Map framework name -> list of (location, size)
        var frameworkLocations: [String: [(location: String, size: UInt64)]] = [:]

        for fw in mainFrameworks {
            frameworkLocations[fw.name, default: []].append(("main", fw.totalSize))
        }

        for ext in extensions {
            for fw in ext.frameworks {
                frameworkLocations[fw.name, default: []].append((ext.name, fw.totalSize))
            }
        }

        // Only report frameworks that appear in 2+ locations
        return frameworkLocations.compactMap { name, locations in
            guard locations.count >= 2 else { return nil }

            let sizePerCopy = locations.map(\.size).max() ?? 0
            let savings = sizePerCopy * UInt64(locations.count - 1)

            return DuplicatedFramework(
                name: name,
                sizePerCopy: sizePerCopy,
                locations: locations.map(\.location),
                potentialSavings: savings
            )
        }
    }
}
