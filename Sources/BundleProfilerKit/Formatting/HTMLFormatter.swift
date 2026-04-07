//
//  HTMLFormatter.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Formats bundle analysis as a self-contained HTML treemap report.
public struct HTMLFormatter: Sendable {
    public init() {}

    /// Format a BundleInfo as a self-contained HTML document with an interactive treemap.
    public func format(bundle: BundleInfo) throws -> String {
        let rootJSON = buildTreeJSON(from: bundle)
        let jsonData = try JSONSerialization.data(withJSONObject: rootJSON, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let insightsJSON = try buildInsightsJSON(from: bundle)
        let css = try Self.loadResource("report", withExtension: "css")
        let javascript = try Self.loadResource("report", withExtension: "js")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Bundle Report — \(escapeHTML(bundle.bundleName))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <div id="header">
          <h1>\(escapeHTML(bundle.bundleName))</h1>
          <span class="total">Total: \(SizeFormatter.format(bundle.totalSize))</span>
        </div>
        <div id="search-container">
          <input id="search" type="text" placeholder="Search files..." />
          <div id="search-results"></div>
        </div>
        <h2 class="section-title">Size Analysis</h2>
        <div id="legend"></div>
        <div id="view-modes">
          <button class="mode-btn active" data-mode="treemap">Treemap</button>
          <button class="mode-btn" data-mode="pie">Pie</button>
          <button class="mode-btn" data-mode="donut">Donut</button>
        </div>
        <div id="breadcrumb"></div>
        <div id="treemap"></div>
        <div id="tooltip"></div>
        <div id="insights"></div>
        <div id="dependency-graph"></div>
        <script>
        const DATA = \(jsonString);
        const INSIGHTS = \(insightsJSON);
        const DEP_GRAPH = \(try buildDependencyGraphJSON(from: bundle));
        \(javascript)
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Insights JSON
    private func buildInsightsJSON(from bundle: BundleInfo) throws -> String {
        let insights = InsightGenerator.generate(from: bundle)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(insights)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Tree Building
    private func buildTreeJSON(from bundle: BundleInfo) -> [String: Any] {
        let files = bundle.files
        let bundleName = bundle.bundleName

        // Build nested dictionary tree from flat file paths
        var root: [String: Any] = ["name": bundleName, "size": 0 as UInt64]
        var rootChildren: [[String: Any]] = []

        // Group files by top-level directory
        var dirMap: [String: [FileEntry]] = [:]
        var topFiles: [FileEntry] = []

        for file in files {
            let components = file.relativePath.split(separator: "/", maxSplits: 1).map(String.init)
            if components.count == 1 {
                topFiles.append(file)
            } else {
                dirMap[components[0], default: []].append(
                    FileEntry(
                        relativePath: String(components[1]),
                        size: file.size,
                        category: file.category,
                        contentHash: file.contentHash
                    )
                )
            }
        }

        // Build directory nodes recursively
        for (dirName, dirFiles) in dirMap.sorted(by: { $0.value.reduce(0) { $0 + $1.size } > $1.value.reduce(0) { $0 + $1.size } }) {
            rootChildren.append(buildDirectoryJSON(name: dirName, files: dirFiles))
        }

        // Add top-level files
        for file in topFiles.sorted(by: { $0.size > $1.size }) {
            rootChildren.append([
                "name": file.relativePath,
                "size": file.size,
                "category": file.category.rawValue,
            ] as [String: Any])
        }

        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }
        root["size"] = totalSize
        root["children"] = rootChildren

        // Post-processing: inject asset catalog children into .car leaf nodes
        // Process root's children directly so the bundle name isn't prepended to paths
        // (AssetCatalogInfo.path is relative to the bundle root, e.g. "Assets.car")
        let catalogLookup = Dictionary(
            bundle.assetCatalogs.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        if !catalogLookup.isEmpty, var rootChildren = root["children"] as? [[String: Any]] {
            rootChildren = rootChildren.map { child in
                injectAssetCatalogs(into: child, currentPath: "", lookup: catalogLookup)
            }
            root["children"] = rootChildren
        }

        // Post-processing: inject framework binary composition
        let frameworkLookup = Dictionary(
            bundle.frameworks.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        if !frameworkLookup.isEmpty {
            root = injectFrameworkComposition(into: root, lookup: frameworkLookup)
        }

        // Post-processing: inject SPM package grouping
        if !bundle.spmPackages.isEmpty {
            root = injectSPMPackages(into: root, packages: bundle.spmPackages)
        }

        // Post-processing: inject extension composition
        if let extReport = bundle.extensionReport, !extReport.extensions.isEmpty {
            root = injectExtensionComposition(into: root, extensions: extReport.extensions)
        }

        return root
    }

    private func buildDirectoryJSON(name: String, files: [FileEntry]) -> [String: Any] {
        var children: [[String: Any]] = []
        var subDirs: [String: [FileEntry]] = [:]
        var directFiles: [FileEntry] = []

        for file in files {
            let components = file.relativePath.split(separator: "/", maxSplits: 1).map(String.init)
            if components.count == 1 {
                directFiles.append(file)
            } else {
                subDirs[components[0], default: []].append(
                    FileEntry(
                        relativePath: String(components[1]),
                        size: file.size,
                        category: file.category,
                        contentHash: file.contentHash
                    )
                )
            }
        }

        for (dirName, dirFiles) in subDirs.sorted(by: { $0.value.reduce(0) { $0 + $1.size } > $1.value.reduce(0) { $0 + $1.size } }) {
            children.append(buildDirectoryJSON(name: dirName, files: dirFiles))
        }

        for file in directFiles.sorted(by: { $0.size > $1.size }) {
            children.append([
                "name": file.relativePath,
                "size": file.size,
                "category": file.category.rawValue,
            ] as [String: Any])
        }

        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }
        return [
            "name": name,
            "size": totalSize,
            "children": children,
        ] as [String: Any]
    }

    // MARK: - Asset Catalog Injection
    private func injectAssetCatalogs(
        into node: [String: Any],
        currentPath: String,
        lookup: [String: AssetCatalogInfo]
    ) -> [String: Any] {
        guard var children = node["children"] as? [[String: Any]] else {
            // Leaf node — check if it's a .car file
            let name = node["name"] as? String ?? ""
            guard name.hasSuffix(".car") else { return node }

            let matchPath = currentPath.isEmpty ? name : currentPath + "/" + name
            guard let catalog = lookup[matchPath], !catalog.assets.isEmpty else { return node }

            let assetChildren = buildAssetChildren(from: catalog)
            var dirNode = node
            dirNode["children"] = assetChildren
            dirNode.removeValue(forKey: "category")
            return dirNode
        }

        let nodeName = node["name"] as? String ?? ""
        let childPath = currentPath.isEmpty ? nodeName : currentPath + "/" + nodeName

        children = children.map { child in
            injectAssetCatalogs(into: child, currentPath: childPath, lookup: lookup)
        }

        var updated = node
        updated["children"] = children
        return updated
    }

    private func buildAssetChildren(from catalog: AssetCatalogInfo) -> [[String: Any]] {
        let sortedAssets = catalog.assets.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        var children: [[String: Any]] = sortedAssets.map { asset in
            [
                "name": asset.renditionName ?? asset.name,
                "size": asset.size ?? 0,
                "category": FileCategory.assetCatalog.rawValue,
            ] as [String: Any]
        }

        let assetSum = catalog.assets.reduce(UInt64(0)) { $0 + ($1.size ?? 0) }
        if catalog.fileSize > assetSum {
            children.append([
                "name": "(catalog overhead)",
                "size": catalog.fileSize - assetSum,
                "category": FileCategory.assetCatalog.rawValue,
            ] as [String: Any])
        }

        return children
    }

    // MARK: - Framework Composition Injection
    private func injectFrameworkComposition(
        into node: [String: Any],
        lookup: [String: FrameworkInfo]
    ) -> [String: Any] {
        guard var children = node["children"] as? [[String: Any]] else { return node }

        children = children.map { child in
            let childName = child["name"] as? String ?? ""

            // Check if this directory matches a framework (e.g. "Alamofire.framework")
            if childName.hasSuffix(".framework"),
               let fwName = childName.split(separator: ".").first.map(String.init),
               let fw = lookup[fwName] {
                return buildFrameworkNode(from: fw, originalNode: child)
            }

            // Recurse into directories
            return injectFrameworkComposition(into: child, lookup: lookup)
        }

        var updated = node
        updated["children"] = children
        return updated
    }

    private func buildFrameworkNode(from fw: FrameworkInfo, originalNode: [String: Any]) -> [String: Any] {
        var structuredChildren: [[String: Any]] = []
        let originalChildren = originalNode["children"] as? [[String: Any]] ?? []

        // Binary node with optional Mach-O segment breakdown
        var binaryNode: [String: Any] = [
            "name": fw.name,
            "size": fw.binarySize,
            "category": FileCategory.executable.rawValue,
        ]
        if let machO = fw.machOInfo {
            let slice = machO.slices.first(where: { $0.architecture == "arm64" }) ?? machO.slices.first
            if let slice, !slice.segments.isEmpty {
                let segmentChildren: [[String: Any]] = slice.segments
                    .filter { $0.fileSize > 0 }
                    .sorted { $0.fileSize > $1.fileSize }
                    .map { segment in
                        [
                            "name": segment.name,
                            "size": segment.fileSize,
                            "category": FileCategory.executable.rawValue,
                        ] as [String: Any]
                    }
                if !segmentChildren.isEmpty {
                    binaryNode["children"] = segmentChildren
                }
            }
        }
        structuredChildren.append(binaryNode)

        // Resources node — original children minus binary and code signature
        let resourceChildren = originalChildren.filter { child in
            let name = child["name"] as? String ?? ""
            let category = child["category"] as? String
            return name != fw.name && category != FileCategory.codeSignature.rawValue
                && !name.contains("_CodeSignature")
        }
        if fw.resourceSize > 0 {
            structuredChildren.append([
                "name": "Resources",
                "size": fw.resourceSize,
                "children": resourceChildren,
            ] as [String: Any])
        }

        // Code Signature node
        if fw.codeSignatureSize > 0 {
            structuredChildren.append([
                "name": "Code Signature",
                "size": fw.codeSignatureSize,
                "category": FileCategory.codeSignature.rawValue,
            ] as [String: Any])
        }

        var node = originalNode
        node["children"] = structuredChildren
        return node
    }

    // MARK: - Dependency Graph JSON
    private func buildDependencyGraphJSON(from bundle: BundleInfo) throws -> String {
        guard let graph = bundle.dependencyGraph else { return "null" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(graph)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    // MARK: - SPM Package Injection
    private func injectSPMPackages(into root: [String: Any], packages: [SPMPackageInfo]) -> [String: Any] {
        // Add a virtual "SPM Packages" grouping that attributes sizes to packages
        guard var rootChildren = root["children"] as? [[String: Any]] else { return root }

        var spmChildren: [[String: Any]] = []
        for pkg in packages {
            var pkgChildren: [[String: Any]] = []

            if let fw = pkg.dynamicFramework {
                pkgChildren.append([
                    "name": "\(fw.name).framework",
                    "size": fw.totalSize,
                    "category": FileCategory.framework.rawValue,
                ] as [String: Any])
            }

            for rb in pkg.resourceBundles {
                pkgChildren.append([
                    "name": rb.name + ".bundle",
                    "size": rb.totalSize,
                    "category": FileCategory.other.rawValue,
                ] as [String: Any])
            }

            for mod in pkg.swiftModules {
                pkgChildren.append([
                    "name": mod.moduleName + ".swiftmodule",
                    "size": mod.size,
                    "category": FileCategory.other.rawValue,
                ] as [String: Any])
            }

            if !pkgChildren.isEmpty {
                spmChildren.append([
                    "name": pkg.name,
                    "size": pkg.totalSize,
                    "children": pkgChildren,
                ] as [String: Any])
            }
        }

        if !spmChildren.isEmpty {
            let totalSPM = packages.reduce(UInt64(0)) { $0 + $1.totalSize }
            rootChildren.append([
                "name": "(SPM Packages)",
                "size": totalSPM,
                "children": spmChildren,
            ] as [String: Any])
        }

        var updated = root
        updated["children"] = rootChildren
        return updated
    }

    // MARK: - Extension Composition Injection
    private func injectExtensionComposition(
        into root: [String: Any],
        extensions: [AppExtensionInfo]
    ) -> [String: Any] {
        guard var rootChildren = root["children"] as? [[String: Any]] else { return root }

        // Find and enhance the PlugIns directory node
        rootChildren = rootChildren.map { child in
            let name = child["name"] as? String ?? ""
            guard name == "PlugIns", var children = child["children"] as? [[String: Any]] else {
                return child
            }

            let extLookup = Dictionary(
                extensions.map { ($0.name + ".appex", $0) },
                uniquingKeysWith: { first, _ in first }
            )

            children = children.map { appexNode in
                let appexName = appexNode["name"] as? String ?? ""
                guard let ext = extLookup[appexName] else { return appexNode }

                var structuredChildren: [[String: Any]] = []

                // Executable
                if ext.executableSize > 0 {
                    structuredChildren.append([
                        "name": ext.name,
                        "size": ext.executableSize,
                        "category": FileCategory.executable.rawValue,
                    ] as [String: Any])
                }

                // Frameworks
                if !ext.frameworks.isEmpty {
                    let fwChildren: [[String: Any]] = ext.frameworks.map { fw in
                        [
                            "name": fw.name + ".framework",
                            "size": fw.totalSize,
                            "category": FileCategory.framework.rawValue,
                        ] as [String: Any]
                    }
                    let fwTotal = ext.frameworks.reduce(UInt64(0)) { $0 + $1.totalSize }
                    structuredChildren.append([
                        "name": "Frameworks",
                        "size": fwTotal,
                        "children": fwChildren,
                    ] as [String: Any])
                }

                // Resources (remaining size)
                let accounted = ext.executableSize + ext.frameworks.reduce(UInt64(0)) { $0 + $1.totalSize }
                if ext.totalSize > accounted {
                    structuredChildren.append([
                        "name": "Resources",
                        "size": ext.totalSize - accounted,
                        "category": FileCategory.other.rawValue,
                    ] as [String: Any])
                }

                var updated = appexNode
                updated["children"] = structuredChildren
                return updated
            }

            var updated = child
            updated["children"] = children
            return updated
        }

        var updated = root
        updated["children"] = rootChildren
        return updated
    }

    // MARK: - HTML Escaping
    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Resource Loading
    private enum ResourceError: Error, CustomStringConvertible {
        case missingResource(name: String, extension: String)

        var description: String {
            switch self {
            case .missingResource(let name, let ext):
                return "Missing bundled resource: \(name).\(ext)"
            }
        }
    }

    private static func loadResource(_ name: String, withExtension ext: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw ResourceError.missingResource(name: name, extension: ext)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
