//
//  MarkdownFormatter.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Formats analysis results as Markdown (suitable for PR comments).
public struct MarkdownFormatter: Sendable {
    public init() {}

    // MARK: - Budget Result
    /// Format a budget check result as Markdown.
    public func format(budget: BudgetResult) -> String {
        var lines: [String] = []

        let status = budget.isOverBudget ? "OVER BUDGET" : "UNDER BUDGET"
        let emoji = budget.isOverBudget ? "x" : "white_check_mark"
        lines.append("## :\(emoji): Bundle Size Check — \(status)")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")
        lines.append("| Bundle | \(budget.bundleName) |")
        lines.append("| Total Size | \(SizeFormatter.format(budget.totalSize)) |")
        lines.append("| Budget | \(SizeFormatter.format(budget.budget)) |")
        lines.append("| Delta | \(SizeFormatter.formatDelta(budget.delta)) |")

        // Category breakdown
        let sorted = budget.categoryBreakdown.sorted { $0.value > $1.value }
        if !sorted.isEmpty {
            lines.append("")
            lines.append("### Category Breakdown")
            lines.append("")
            lines.append("| Category | Size | % |")
            lines.append("|----------|------|---|")
            for (category, size) in sorted {
                let pct = budget.totalSize > 0
                    ? SizeFormatter.formatPercentage(Double(size) / Double(budget.totalSize))
                    : "0.0%"
                lines.append("| \(category.displayName) | \(SizeFormatter.format(size)) | \(pct) |")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Bundle Analysis
    /// Format a bundle analysis as Markdown.
    public func format(bundle: BundleInfo) -> String {
        var lines: [String] = []

        lines.append("## Bundle Analysis: \(bundle.bundleName)")
        lines.append("")
        lines.append("**Total Size:** \(SizeFormatter.format(bundle.totalSize))")
        lines.append("")

        // Category breakdown
        let sorted = bundle.categoryBreakdown.sorted { $0.value > $1.value }
        if !sorted.isEmpty {
            lines.append("### Category Breakdown")
            lines.append("")
            lines.append("| Category | Size | % |")
            lines.append("|----------|------|---|")
            for (category, size) in sorted {
                let pct = bundle.totalSize > 0
                    ? SizeFormatter.formatPercentage(Double(size) / Double(bundle.totalSize))
                    : "0.0%"
                lines.append("| \(category.displayName) | \(SizeFormatter.format(size)) | \(pct) |")
            }
            lines.append("")
        }

        // Frameworks
        if !bundle.frameworks.isEmpty {
            lines.append("### Embedded Frameworks")
            lines.append("")
            lines.append("| Framework | Total | Binary | Resources |")
            lines.append("|-----------|-------|--------|-----------|")
            for fw in bundle.frameworks {
                lines.append("| \(fw.name) | \(SizeFormatter.format(fw.totalSize)) | \(SizeFormatter.format(fw.binarySize)) | \(SizeFormatter.format(fw.resourceSize)) |")
            }
            lines.append("")
        }

        // Asset catalogs
        let nonEmptyCatalogs = bundle.assetCatalogs.filter { $0.assetCount > 0 }
        if !nonEmptyCatalogs.isEmpty {
            lines.append("### Asset Catalogs")
            lines.append("")
            for catalog in nonEmptyCatalogs {
                let catalogName = (catalog.path as NSString).lastPathComponent
                lines.append("**\(catalogName)** — \(SizeFormatter.format(catalog.fileSize)) (\(catalog.assetCount) assets)")
                lines.append("")
                let sorted = catalog.assets.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
                let top10 = sorted.prefix(10)
                if !top10.isEmpty {
                    lines.append("| Asset | Size |")
                    lines.append("|-------|------|")
                    for asset in top10 {
                        let name = asset.renditionName ?? asset.name
                        let size = SizeFormatter.format(asset.size ?? 0)
                        lines.append("| \(name) | \(size) |")
                    }
                    let remaining = sorted.count - top10.count
                    if remaining > 0 {
                        lines.append("")
                        lines.append("*... and \(remaining) more assets*")
                    }
                    lines.append("")
                }
            }
        }

        // Duplicates
        if !bundle.duplicates.isEmpty {
            lines.append("### Duplicate Resources")
            lines.append("")
            lines.append("**Wasted:** \(SizeFormatter.format(bundle.totalWastedBytes))")
            lines.append("")
            lines.append("| File | Size | Copies | Wasted |")
            lines.append("|------|------|--------|--------|")
            for group in bundle.duplicates.prefix(20) {
                let filename = (group.paths.first.map { ($0 as NSString).lastPathComponent }) ?? "?"
                lines.append("| \(filename) | \(SizeFormatter.format(group.fileSize)) | \(group.paths.count) | \(SizeFormatter.format(group.wastedBytes)) |")
            }
            lines.append("")
        }

        // SPM Packages
        if !bundle.spmPackages.isEmpty {
            lines.append("### SPM Packages")
            lines.append("")
            lines.append("| Package | Total | Framework | Resources | Modules |")
            lines.append("|---------|-------|-----------|-----------|---------|")
            for pkg in bundle.spmPackages {
                let fwSize = pkg.dynamicFramework.map { SizeFormatter.format($0.totalSize) } ?? "-"
                let resSize = pkg.resourceBundles.isEmpty ? "-" : SizeFormatter.format(pkg.resourceBundles.reduce(0) { $0 + $1.totalSize })
                let modSize = pkg.swiftModules.isEmpty ? "-" : SizeFormatter.format(pkg.swiftModules.reduce(0) { $0 + $1.size })
                lines.append("| \(pkg.name) | \(SizeFormatter.format(pkg.totalSize)) | \(fwSize) | \(resSize) | \(modSize) |")
            }
            lines.append("")
        }

        // Unused Resources
        if let report = bundle.unusedResources, !report.unusedResources.isEmpty {
            lines.append("### Unused Resources")
            lines.append("")
            lines.append("**Potential savings:** \(SizeFormatter.format(report.potentialSavings)) (\(report.unusedResources.count) of \(report.totalResourcesScanned) resources)")
            lines.append("")
            lines.append("| Resource | Size | Category |")
            lines.append("|----------|------|----------|")
            for resource in report.unusedResources.prefix(30) {
                lines.append("| \(resource.relativePath) | \(SizeFormatter.format(resource.fileSize)) | \(resource.category.displayName) |")
            }
            if report.unusedResources.count > 30 {
                lines.append("")
                lines.append("*... and \(report.unusedResources.count - 30) more*")
            }
            lines.append("")
            lines.append("> **Limitations:** \(report.limitations.joined(separator: ". "))")
            lines.append("")
        }

        // App Extensions
        if let report = bundle.extensionReport {
            lines.append("### App Extensions")
            lines.append("")
            lines.append("**Total extension size:** \(SizeFormatter.format(report.totalExtensionSize))")
            lines.append("")
            lines.append("| Extension | Size | Executable | Frameworks |")
            lines.append("|-----------|------|------------|------------|")
            for ext in report.extensions {
                lines.append("| \(ext.name) | \(SizeFormatter.format(ext.totalSize)) | \(SizeFormatter.format(ext.executableSize)) | \(ext.frameworks.count) |")
            }
            lines.append("")

            if !report.duplicatedFrameworks.isEmpty {
                lines.append("#### Duplicated Frameworks")
                lines.append("")
                lines.append("**Potential savings:** \(SizeFormatter.format(report.potentialSavings))")
                lines.append("")
                lines.append("| Framework | Size/Copy | Copies | Locations | Savings |")
                lines.append("|-----------|----------|--------|-----------|---------|")
                for dup in report.duplicatedFrameworks {
                    lines.append("| \(dup.name) | \(SizeFormatter.format(dup.sizePerCopy)) | \(dup.locations.count) | \(dup.locations.joined(separator: ", ")) | \(SizeFormatter.format(dup.potentialSavings)) |")
                }
                lines.append("")
            }
        }

        // Dependency Graph
        if let graph = bundle.dependencyGraph {
            let embedded = graph.nodes.filter { $0.nodeType == .embeddedFramework }
            lines.append("### Dependency Graph")
            lines.append("")
            lines.append("| Binary | Dependencies | Size | Type |")
            lines.append("|--------|-------------|------|------|")
            let edgeMap = Dictionary(grouping: graph.edges, by: \.from)
            for node in graph.nodes where !node.isSystemLibrary {
                let depCount = edgeMap[node.name]?.count ?? 0
                lines.append("| \(node.name) | \(depCount) | \(SizeFormatter.format(node.binarySize)) | \(node.nodeType.rawValue) |")
            }
            lines.append("")

            if graph.heaviestChain.path.count > 1 {
                lines.append("#### Heaviest Dependency Chain")
                lines.append("")
                lines.append("**\(SizeFormatter.format(graph.heaviestChain.totalSize))** — \(graph.heaviestChain.path.joined(separator: " -> "))")
                lines.append("")
            }

            if !embedded.isEmpty {
                let systemCount = graph.nodes.filter(\.isSystemLibrary).count
                lines.append("*\(embedded.count) embedded frameworks, \(systemCount) system libraries, max depth \(graph.maxDepth)*")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Comparison
    /// Format a comparison result as Markdown.
    public func format(comparison: ComparisonResult) -> String {
        var lines: [String] = []

        lines.append("## Bundle Comparison")
        lines.append("")
        lines.append("| | Bundle | Size |")
        lines.append("|---|--------|------|")
        lines.append("| Baseline | \(comparison.baselineName) | \(SizeFormatter.format(comparison.baselineSize)) |")
        lines.append("| Current | \(comparison.currentName) | \(SizeFormatter.format(comparison.currentSize)) |")
        lines.append("| **Delta** | | **\(SizeFormatter.formatDelta(comparison.sizeDelta))** |")
        lines.append("")

        // Category deltas
        if !comparison.categoryDeltas.isEmpty {
            lines.append("### Category Deltas")
            lines.append("")
            lines.append("| Category | Delta |")
            lines.append("|----------|-------|")
            for delta in comparison.categoryDeltas {
                lines.append("| \(delta.category.displayName) | \(SizeFormatter.formatDelta(delta.delta)) |")
            }
            lines.append("")
        }

        // Added / removed / changed counts
        if !comparison.addedFiles.isEmpty {
            lines.append("**Added files:** \(comparison.addedFiles.count)")
            lines.append("")
        }
        if !comparison.removedFiles.isEmpty {
            lines.append("**Removed files:** \(comparison.removedFiles.count)")
            lines.append("")
        }
        if !comparison.changedFiles.isEmpty {
            lines.append("**Changed files:** \(comparison.changedFiles.count)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
