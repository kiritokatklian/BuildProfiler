//
//  TreeFormatter.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Formats analysis results as human-readable tree output with bar charts.
public struct TreeFormatter: Sendable {
    private static let lineWidth = 80
    private static let barMaxWidth = 20

    public init() {}

    // MARK: - Bundle Analysis
    public func format(bundle: BundleInfo, topN: Int? = nil) -> String {
        var lines: [String] = []

        // Header
        let header = "\(bundle.bundleName)"
        let totalStr = "Total: \(SizeFormatter.format(bundle.totalSize))"
        let padding = max(0, Self.lineWidth - header.count - totalStr.count)
        lines.append(header + String(repeating: " ", count: padding) + totalStr)
        lines.append(String(repeating: "=", count: Self.lineWidth))

        // Category breakdown
        lines.append("")
        lines.append("CATEGORY BREAKDOWN")
        lines.append(String(repeating: "-", count: Self.lineWidth))
        lines.append(contentsOf: self.formatCategoryBreakdown(bundle: bundle))

        // Mach-O analysis
        if let machO = bundle.mainExecutable {
            lines.append("")
            lines.append(contentsOf: self.formatMachOInfo(machO))
        }

        // App thinning estimates
        if bundle.mainExecutable != nil {
            let simulator = ThinningSimulator()
            let report = simulator.simulate(bundle: bundle)
            if !report.estimates.isEmpty {
                lines.append("")
                lines.append("APP THINNING ESTIMATES")
                lines.append(String(repeating: "-", count: Self.lineWidth))
                lines.append("  \("Architecture".padding(toLength: 14, withPad: " ", startingAt: 0)) \("Estimated".padding(toLength: 12, withPad: " ", startingAt: 0)) \("Binary".padding(toLength: 12, withPad: " ", startingAt: 0)) Resources")
                for estimate in report.estimates {
                    let arch = estimate.architecture.padding(toLength: 14, withPad: " ", startingAt: 0)
                    let est = SizeFormatter.padded(estimate.estimatedSize, width: 12)
                    let bin = SizeFormatter.padded(estimate.binarySize, width: 12)
                    let res = SizeFormatter.format(estimate.resourceSize)
                    lines.append("  \(arch) \(est) \(bin) \(res)")
                }
            }
        }

        // Embedded frameworks
        if !bundle.frameworks.isEmpty {
            lines.append("")
            lines.append("EMBEDDED FRAMEWORKS")
            lines.append(String(repeating: "-", count: Self.lineWidth))
            lines.append(contentsOf: self.formatFrameworks(bundle.frameworks))
        }

        // Asset catalogs
        if !bundle.assetCatalogs.isEmpty {
            let nonEmpty = bundle.assetCatalogs.filter { $0.assetCount > 0 }
            if !nonEmpty.isEmpty {
                lines.append("")
                lines.append("ASSET CATALOGS")
                lines.append(String(repeating: "-", count: Self.lineWidth))
                lines.append(contentsOf: self.formatAssetCatalogs(nonEmpty))
            }
        }

        // Duplicate resources
        if !bundle.duplicates.isEmpty {
            lines.append("")
            let wastedStr = "Wasted: \(SizeFormatter.format(bundle.totalWastedBytes))"
            let dupHeader = "DUPLICATE RESOURCES"
            let dupPadding = max(0, Self.lineWidth - dupHeader.count - wastedStr.count)
            lines.append(dupHeader + String(repeating: " ", count: dupPadding) + wastedStr)
            lines.append(String(repeating: "-", count: Self.lineWidth))
            lines.append(contentsOf: self.formatDuplicates(bundle.duplicates))
        }

        // Top files
        let topCount = topN ?? 20
        lines.append("")
        lines.append("TOP \(topCount) LARGEST FILES")
        lines.append(String(repeating: "-", count: Self.lineWidth))
        lines.append(contentsOf: self.formatTopFiles(files: bundle.files, count: topCount))

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Comparison
    public func format(comparison: ComparisonResult) -> String {
        var lines: [String] = []

        // Header
        lines.append("BUNDLE COMPARISON")
        lines.append(String(repeating: "=", count: Self.lineWidth))
        lines.append("  Baseline: \(comparison.baselineName)  \(SizeFormatter.format(comparison.baselineSize))")
        lines.append("  Current:  \(comparison.currentName)  \(SizeFormatter.format(comparison.currentSize))")
        lines.append("  Delta:    \(SizeFormatter.formatDelta(comparison.sizeDelta))")

        // Category deltas
        if !comparison.categoryDeltas.isEmpty {
            lines.append("")
            lines.append("CATEGORY DELTAS")
            lines.append(String(repeating: "-", count: Self.lineWidth))
            for delta in comparison.categoryDeltas {
                let name = delta.category.displayName.padding(toLength: 22, withPad: " ", startingAt: 0)
                let size = SizeFormatter.paddedDelta(delta.delta)
                lines.append("  \(name) \(size)")
            }
        }

        // Framework deltas
        if !comparison.frameworkDeltas.isEmpty {
            lines.append("")
            lines.append("FRAMEWORK DELTAS")
            lines.append(String(repeating: "-", count: Self.lineWidth))
            for delta in comparison.frameworkDeltas {
                let name = delta.name.padding(toLength: 22, withPad: " ", startingAt: 0)
                let size = SizeFormatter.paddedDelta(delta.delta)
                lines.append("  \(name) \(size)")
            }
        }

        // Added files
        if !comparison.addedFiles.isEmpty {
            lines.append("")
            lines.append("ADDED FILES (\(comparison.addedFiles.count))")
            lines.append(String(repeating: "-", count: Self.lineWidth))
            for file in comparison.addedFiles.prefix(20) {
                lines.append("  + \(SizeFormatter.padded(file.size, width: 10))  \(file.relativePath)")
            }
            if comparison.addedFiles.count > 20 {
                lines.append("  ... and \(comparison.addedFiles.count - 20) more")
            }
        }

        // Removed files
        if !comparison.removedFiles.isEmpty {
            lines.append("")
            lines.append("REMOVED FILES (\(comparison.removedFiles.count))")
            lines.append(String(repeating: "-", count: Self.lineWidth))
            for file in comparison.removedFiles.prefix(20) {
                lines.append("  - \(SizeFormatter.padded(file.size, width: 10))  \(file.relativePath)")
            }
            if comparison.removedFiles.count > 20 {
                lines.append("  ... and \(comparison.removedFiles.count - 20) more")
            }
        }

        // Changed files
        if !comparison.changedFiles.isEmpty {
            lines.append("")
            lines.append("CHANGED FILES (\(comparison.changedFiles.count))")
            lines.append(String(repeating: "-", count: Self.lineWidth))
            for delta in comparison.changedFiles.prefix(30) {
                let size = SizeFormatter.paddedDelta(delta.delta)
                lines.append("  \(size)  \(delta.relativePath)")
            }
            if comparison.changedFiles.count > 30 {
                lines.append("  ... and \(comparison.changedFiles.count - 30) more")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting Helpers
    private func formatCategoryBreakdown(bundle: BundleInfo) -> [String] {
        let sorted = bundle.categoryBreakdown
            .sorted { $0.value > $1.value }

        let maxSize = sorted.first?.value ?? 1

        return sorted.map { category, size in
            let name = category.displayName.padding(toLength: 22, withPad: " ", startingAt: 0)
            let sizeStr = SizeFormatter.padded(size)
            let pct = bundle.totalSize > 0 ? Double(size) / Double(bundle.totalSize) : 0
            let pctStr = SizeFormatter.formatPercentage(pct).padding(toLength: 7, withPad: " ", startingAt: 0)
            let barWidth = maxSize > 0 ? Int(Double(size) / Double(maxSize) * Double(Self.barMaxWidth)) : 0
            let bar = String(repeating: "\u{2588}", count: max(barWidth, 0))
            return "  \(name) \(sizeStr)  \(pctStr)  \(bar)"
        }
    }

    private func formatMachOInfo(_ machO: MachOInfo) -> [String] {
        var lines: [String] = []

        for slice in machO.slices {
            lines.append("MACH-O ANALYSIS: \(machO.name) (\(slice.architecture))")
            lines.append(String(repeating: "-", count: Self.lineWidth))

            let totalSegSize = slice.segments.reduce(UInt64(0)) { $0 + $1.fileSize }

            for segment in slice.segments where segment.fileSize > 0 {
                let name = segment.name.padding(toLength: 16, withPad: " ", startingAt: 0)
                let sizeStr = SizeFormatter.padded(segment.fileSize)
                let pct = totalSegSize > 0 ? Double(segment.fileSize) / Double(totalSegSize) : 0
                let pctStr = SizeFormatter.formatPercentage(pct)
                lines.append("    \(name) \(sizeStr)  \(pctStr)")

                // Show sections if they exist
                for section in segment.sections where section.size > 0 {
                    let sectName = section.name.padding(toLength: 22, withPad: " ", startingAt: 0)
                    let sectSize = SizeFormatter.padded(section.size, width: 10)
                    lines.append("      \(sectName) \(sectSize)")
                }
            }

            // Linked libraries
            if !slice.dependencies.isEmpty {
                lines.append("")
                lines.append("  Linked Libraries (\(slice.dependencies.count)):")
                for dep in slice.dependencies {
                    let tag: String
                    switch dep.type {
                    case .load: tag = ""
                    case .weak: tag = " [weak]"
                    case .reexport: tag = " [reexport]"
                    case .lazy: tag = " [lazy]"
                    }
                    let shortName = (dep.name as NSString).lastPathComponent
                    lines.append("    \(shortName)\(tag)  (compat: \(dep.compatibilityVersion), current: \(dep.currentVersion))")
                }
            }
        }

        return lines
    }

    private func formatFrameworks(_ frameworks: [FrameworkInfo]) -> [String] {
        frameworks.map { fw in
            let name = "\(fw.name).framework".padding(toLength: 30, withPad: " ", startingAt: 0)
            let total = SizeFormatter.padded(fw.totalSize)
            let binary = SizeFormatter.format(fw.binarySize)
            let resources = SizeFormatter.format(fw.resourceSize)
            return "  \(name) \(total)    (binary: \(binary), resources: \(resources))"
        }
    }

    private func formatAssetCatalogs(_ catalogs: [AssetCatalogInfo]) -> [String] {
        catalogs.map { cat in
            let path = cat.path.padding(toLength: 30, withPad: " ", startingAt: 0)
            let size = SizeFormatter.padded(cat.fileSize)
            return "  \(path) \(size)    (\(cat.assetCount) assets)"
        }
    }

    private func formatDuplicates(_ duplicates: [DuplicateGroup]) -> [String] {
        duplicates.prefix(20).map { group in
            let filename = (group.paths.first.map { ($0 as NSString).lastPathComponent }) ?? "?"
            let copies = "\(SizeFormatter.format(group.fileSize)) x \(group.paths.count) copies"
            let wasted = "Wasted: \(SizeFormatter.format(group.wastedBytes))"
            return "  \(filename) (\(copies))    \(wasted)"
        }
    }

    private func formatTopFiles(files: [FileEntry], count: Int) -> [String] {
        Array(files.prefix(count)).map { file in
            let size = SizeFormatter.padded(file.size)
            return "  \(size)  \(file.relativePath)"
        }
    }
}
