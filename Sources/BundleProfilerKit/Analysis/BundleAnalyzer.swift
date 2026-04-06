//
//  BundleAnalyzer.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Orchestrates the complete analysis of an app bundle.
public struct BundleAnalyzer: Sendable {
    /// Configuration for the analysis.
    public struct Options: Sendable {
        public var analyzeMachO: Bool
        public var detectDuplicates: Bool
        public var topN: Int?

        public init(analyzeMachO: Bool = true, detectDuplicates: Bool = true, topN: Int? = nil) {
            self.analyzeMachO = analyzeMachO
            self.detectDuplicates = detectDuplicates
            self.topN = topN
        }
    }

    public enum AnalysisError: Error, CustomStringConvertible {
        case bundleNotFound(String)
        case notABundle(String)

        public var description: String {
            switch self {
            case .bundleNotFound(let path): "Bundle not found: \(path)"
            case .notABundle(let path): "Not an app bundle: \(path)"
            }
        }
    }

    private let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Analyze a bundle at the given path (.app directory or .ipa file).
    public func analyze(path: String) throws -> BundleInfo {
        let fileManager = FileManager.default
        var appPath = path
        var tempDir: String?

        // Handle .ipa files
        if path.hasSuffix(".ipa") {
            let result = try IPAExtractor.extract(ipaPath: path)
            appPath = result.appPath
            tempDir = result.tempDirectory
        }

        defer {
            if let tempDir {
                IPAExtractor.cleanUp(tempDirectory: tempDir)
            }
        }

        guard fileManager.fileExists(atPath: appPath) else {
            throw AnalysisError.bundleNotFound(appPath)
        }

        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: appPath, isDirectory: &isDir)
        guard isDir.boolValue else {
            throw AnalysisError.notABundle(appPath)
        }

        let bundleName = (appPath as NSString).lastPathComponent

        // Walk all files
        let skipHashing = !self.options.detectDuplicates
        let walker = FileWalker(bundlePath: appPath, skipHashing: skipHashing)
        let files = try walker.walk()

        // Calculate total size
        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }

        // Build category breakdown
        var categoryBreakdown: [FileCategory: UInt64] = [:]
        for file in files {
            categoryBreakdown[file.category, default: 0] += file.size
        }

        // Analyze main executable
        let mainExecutable: MachOInfo?
        if self.options.analyzeMachO {
            mainExecutable = self.findAndParseMainExecutable(bundlePath: appPath, bundleName: bundleName)
        } else {
            mainExecutable = nil
        }

        // Analyze frameworks
        let frameworks = self.analyzeFrameworks(bundlePath: appPath, files: files)

        // Detect duplicates
        let duplicates: [DuplicateGroup]
        if self.options.detectDuplicates {
            duplicates = DuplicateDetector.detect(files: files)
        } else {
            duplicates = []
        }

        // Analyze asset catalogs
        let assetCatalogs = self.analyzeAssetCatalogs(bundlePath: appPath, files: files)

        return BundleInfo(
            bundleName: bundleName,
            totalSize: totalSize,
            files: files,
            categoryBreakdown: categoryBreakdown,
            mainExecutable: mainExecutable,
            frameworks: frameworks,
            duplicates: duplicates,
            assetCatalogs: assetCatalogs
        )
    }

    // MARK: - Main Executable

    private func findAndParseMainExecutable(bundlePath: String, bundleName: String) -> MachOInfo? {
        let execName = (bundleName as NSString).deletingPathExtension
        let execPath = bundlePath + "/" + execName

        guard FileManager.default.fileExists(atPath: execPath) else { return nil }

        return try? MachOParser.parse(path: execPath)
    }

    // MARK: - Frameworks

    private func analyzeFrameworks(bundlePath: String, files: [FileEntry]) -> [FrameworkInfo] {
        let frameworksDir = bundlePath + "/Frameworks"
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

                // Gather files belonging to this framework
                let prefix = "Frameworks/" + frameworkDir + "/"
                let frameworkFiles = files.filter { $0.relativePath.hasPrefix(prefix) }

                let totalSize = frameworkFiles.reduce(UInt64(0)) { $0 + $1.size }

                // Find binary
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
                if self.options.analyzeMachO, binarySize > 0 {
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

    // MARK: - Asset Catalogs

    private func analyzeAssetCatalogs(bundlePath: String, files: [FileEntry]) -> [AssetCatalogInfo] {
        files
            .filter { $0.category == .assetCatalog }
            .map { file in
                let fullPath = bundlePath + "/" + file.relativePath
                var info = AssetCatalogAnalyzer.analyze(carPath: fullPath, fileSize: file.size)
                // Replace the full path with the relative path for display
                info = AssetCatalogInfo(path: file.relativePath, fileSize: info.fileSize, assetCount: info.assetCount, assets: info.assets)
                return info
            }
    }
}
