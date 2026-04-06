//
//  AssetCatalogAnalyzer.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Analyzes .car (compiled asset catalog) files using assetutil.
public struct AssetCatalogAnalyzer: Sendable {
    /// Analyze a .car file and return asset catalog information.
    public static func analyze(carPath: String, fileSize: UInt64) -> AssetCatalogInfo {
        guard let jsonOutput = runAssetUtil(carPath: carPath),
              let assets = parseAssetUtilOutput(jsonOutput)
        else {
            // Graceful degradation: return basic info without asset details
            return AssetCatalogInfo(
                path: carPath,
                fileSize: fileSize,
                assetCount: 0,
                assets: []
            )
        }

        return AssetCatalogInfo(
            path: carPath,
            fileSize: fileSize,
            assetCount: assets.count,
            assets: assets
        )
    }

    private static func runAssetUtil(carPath: String) -> String? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["assetutil", "--info", carPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()

            // Read all data BEFORE waitUntilExit to avoid pipe buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private static func parseAssetUtilOutput(_ jsonString: String) -> [AssetEntry]? {
        guard let data = jsonString.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }

        var assets: [AssetEntry] = []

        for entry in jsonArray {
            // Skip the first entry which is typically catalog metadata
            guard let name = entry["Name"] as? String else { continue }

            let renditionName = entry["RenditionName"] as? String

            var size: UInt64?
            if let sizeInBits = entry["SizeOnDisk"] as? Int {
                size = UInt64(sizeInBits)
            } else if let totalSize = entry["TotalSize"] as? Int {
                size = UInt64(totalSize)
            }

            assets.append(AssetEntry(name: name, renditionName: renditionName, size: size))
        }

        return assets
    }
}
