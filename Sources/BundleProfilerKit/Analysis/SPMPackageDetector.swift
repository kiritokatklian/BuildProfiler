//
//  SPMPackageDetector.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Detects Swift Package Manager dependencies by recognizing SPM naming conventions.
public struct SPMPackageDetector: Sendable {
    /// Detect SPM packages from the bundle's files and frameworks.
    ///
    /// Detection signals:
    /// 1. Resource bundles matching `PackageName_TargetName.bundle`
    /// 2. `.swiftmodule` directories
    /// 3. Cross-reference framework names against detected package names
    ///
    /// - Note: Statically linked SPM code merges into the main binary and cannot be attributed.
    public static func detect(
        files: [FileEntry],
        frameworks: [FrameworkInfo],
        bundlePath: String
    ) -> [SPMPackageInfo] {
        var packageData: [String: PackageAccumulator] = [:]

        // 1. Detect SPM resource bundles (PackageName_TargetName.bundle)
        detectResourceBundles(files: files, into: &packageData)

        // 2. Detect .swiftmodule files
        detectSwiftModules(files: files, into: &packageData)

        // 3. Cross-reference frameworks with detected package names
        let frameworkNames = Set(frameworks.map(\.name))
        crossReferenceFrameworks(
            frameworks: frameworks,
            frameworkNames: frameworkNames,
            into: &packageData
        )

        // Build final results
        return packageData.values
            .map { accumulator in
                let totalSize =
                    (accumulator.framework?.totalSize ?? 0) +
                    accumulator.resourceBundles.reduce(0) { $0 + $1.totalSize } +
                    accumulator.swiftModules.reduce(0) { $0 + $1.size }

                return SPMPackageInfo(
                    name: accumulator.name,
                    totalSize: totalSize,
                    dynamicFramework: accumulator.framework,
                    resourceBundles: accumulator.resourceBundles,
                    swiftModules: accumulator.swiftModules
                )
            }
            .filter { $0.totalSize > 0 }
            .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Detection Methods
    /// Detect resource bundles following the SPM naming convention: `PackageName_TargetName.bundle`.
    private static func detectResourceBundles(
        files: [FileEntry],
        into packageData: inout [String: PackageAccumulator]
    ) {
        // Group files by their .bundle container
        var bundleFiles: [String: [FileEntry]] = [:]

        for file in files {
            let components = file.relativePath.split(separator: "/").map(String.init)
            for (idx, component) in components.enumerated() {
                if component.hasSuffix(".bundle"), component.contains("_") {
                    let key = components[0 ... idx].joined(separator: "/")
                    bundleFiles[key, default: []].append(file)
                    break
                }
            }
        }

        for (bundlePath, files) in bundleFiles {
            let dirName = (bundlePath as NSString).lastPathComponent
            let bundleName = String(dirName.dropLast(".bundle".count))

            // SPM resource bundles use underscore to separate package and target
            guard let underscoreIdx = bundleName.firstIndex(of: "_") else { continue }
            let packageName = String(bundleName[bundleName.startIndex ..< underscoreIdx])
            guard !packageName.isEmpty else { continue }

            let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }
            let resourceBundle = ResourceBundleInfo(
                name: bundleName,
                path: bundlePath,
                totalSize: totalSize,
                files: files
            )

            let key = packageName.lowercased()
            packageData[key, default: PackageAccumulator(name: packageName)]
                .resourceBundles.append(resourceBundle)
        }
    }

    /// Detect .swiftmodule files in the bundle.
    private static func detectSwiftModules(
        files: [FileEntry],
        into packageData: inout [String: PackageAccumulator]
    ) {
        for file in files {
            guard file.relativePath.contains(".swiftmodule") else { continue }
            // Match paths like Frameworks/X.framework/Modules/X.swiftmodule/...
            let components = file.relativePath.split(separator: "/").map(String.init)
            guard let moduleIdx = components.firstIndex(where: { $0.hasSuffix(".swiftmodule") }) else { continue }

            let moduleName = String(components[moduleIdx].dropLast(".swiftmodule".count))
            guard !moduleName.isEmpty else { continue }

            let moduleInfo = SwiftModuleInfo(
                moduleName: moduleName,
                path: file.relativePath,
                size: file.size
            )

            let key = moduleName.lowercased()
            packageData[key, default: PackageAccumulator(name: moduleName)]
                .swiftModules.append(moduleInfo)
        }
    }

    /// Cross-reference framework names against accumulated package names.
    private static func crossReferenceFrameworks(
        frameworks: [FrameworkInfo],
        frameworkNames: Set<String>,
        into packageData: inout [String: PackageAccumulator]
    ) {
        for framework in frameworks {
            let key = framework.name.lowercased()
            if packageData[key] != nil {
                // Framework matches a detected package name
                packageData[key]!.framework = framework
            } else if frameworkNames.contains(framework.name) {
                // Check if this framework name matches any accumulated package
                // by looking for resource bundles or modules with the same prefix
                for (pkgKey, accumulator) in packageData {
                    let pkgName = accumulator.name
                    if framework.name.lowercased().hasPrefix(pkgName.lowercased()) ||
                       pkgName.lowercased().hasPrefix(framework.name.lowercased())
                    {
                        packageData[pkgKey]!.framework = framework
                        break
                    }
                }
            }
        }
    }

    // MARK: - Internal Accumulator
    /// Temporary structure for collecting package artifacts during detection.
    private struct PackageAccumulator {
        let name: String
        var framework: FrameworkInfo?
        var resourceBundles: [ResourceBundleInfo] = []
        var swiftModules: [SwiftModuleInfo] = []
    }
}
