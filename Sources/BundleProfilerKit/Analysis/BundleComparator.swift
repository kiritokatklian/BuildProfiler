//
//  BundleComparator.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Compares two BundleInfo results to produce a delta report.
public struct BundleComparator: Sendable {
    /// Compare two bundles and return the delta.
    ///
    /// - Parameters:
    ///   - baseline: The older/reference bundle.
    ///   - current: The newer bundle to compare against.
    ///   - threshold: Minimum size delta (in bytes) for a file to appear in changedFiles.
    public static func compare(
        baseline: BundleInfo,
        current: BundleInfo,
        threshold: UInt64 = 0
    ) -> ComparisonResult {
        let baselineFiles = Dictionary(uniqueKeysWithValues: baseline.files.map { ($0.relativePath, $0) })
        let currentFiles = Dictionary(uniqueKeysWithValues: current.files.map { ($0.relativePath, $0) })

        let baselinePaths = Set(baselineFiles.keys)
        let currentPaths = Set(currentFiles.keys)

        // Added files
        let addedFiles = currentPaths.subtracting(baselinePaths)
            .compactMap { currentFiles[$0] }
            .sorted { $0.size > $1.size }

        // Removed files
        let removedFiles = baselinePaths.subtracting(currentPaths)
            .compactMap { baselineFiles[$0] }
            .sorted { $0.size > $1.size }

        // Changed files
        let changedFiles = baselinePaths.intersection(currentPaths)
            .compactMap { path -> FileDelta? in
                guard let base = baselineFiles[path],
                      let curr = currentFiles[path],
                      base.size != curr.size
                else { return nil }

                let delta = abs(Int64(curr.size) - Int64(base.size))
                guard delta >= Int64(threshold) else { return nil }

                return FileDelta(
                    relativePath: path,
                    baselineSize: base.size,
                    currentSize: curr.size
                )
            }
            .sorted { abs($0.delta) > abs($1.delta) }

        // Category deltas
        let allCategories = Set(baseline.categoryBreakdown.keys).union(current.categoryBreakdown.keys)
        let categoryDeltas = allCategories
            .map { category in
                CategoryDelta(
                    category: category,
                    baselineSize: baseline.categoryBreakdown[category] ?? 0,
                    currentSize: current.categoryBreakdown[category] ?? 0
                )
            }
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }

        // Framework deltas
        let baselineFrameworks = Dictionary(uniqueKeysWithValues: baseline.frameworks.map { ($0.name, $0) })
        let currentFrameworks = Dictionary(uniqueKeysWithValues: current.frameworks.map { ($0.name, $0) })
        let allFrameworks = Set(baselineFrameworks.keys).union(currentFrameworks.keys)

        let frameworkDeltas = allFrameworks
            .map { name in
                FrameworkDelta(
                    name: name,
                    baselineSize: baselineFrameworks[name]?.totalSize ?? 0,
                    currentSize: currentFrameworks[name]?.totalSize ?? 0
                )
            }
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }

        return ComparisonResult(
            baselineName: baseline.bundleName,
            currentName: current.bundleName,
            baselineSize: baseline.totalSize,
            currentSize: current.totalSize,
            categoryDeltas: categoryDeltas,
            frameworkDeltas: frameworkDeltas,
            addedFiles: addedFiles,
            removedFiles: removedFiles,
            changedFiles: changedFiles
        )
    }
}
