//
//  CompareCommand.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import ArgumentParser
import BundleProfilerKit
import Foundation

struct CompareCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare two .app bundles or .ipa files.",
        discussion: """
        Diffs a baseline and current bundle to show per-category and per-framework \
        size deltas, plus lists of added, removed, and changed files. Use \
        --threshold to filter noise.
        """
    )

    @Argument(help: "Path to the baseline .app or .ipa.")
    var baseline: String

    @Argument(help: "Path to the current .app or .ipa.")
    var current: String

    @Option(name: .long, help: "Output format: tree (default), json, or markdown.")
    var format: OutputFormat = .tree

    @Option(name: .long, help: "Minimum size delta in bytes to include a file in the report.")
    var threshold: UInt64 = 0

    func run() throws {
        let resolvedBaseline = resolvePath(baseline)
        let resolvedCurrent = resolvePath(current)

        let analyzer = BundleAnalyzer()
        let baselineResult = try analyzer.analyze(path: resolvedBaseline)
        let currentResult = try analyzer.analyze(path: resolvedCurrent)

        let comparison = BundleComparator.compare(
            baseline: baselineResult,
            current: currentResult,
            threshold: self.threshold
        )

        switch self.format {
        case .tree:
            let formatter = TreeFormatter()
            print(formatter.format(comparison: comparison))
        case .json:
            let formatter = JSONFormatter()
            let output = try formatter.format(comparison: comparison)
            print(output)
        case .markdown:
            let formatter = MarkdownFormatter()
            print(formatter.format(comparison: comparison))
        case .html:
            let formatter = TreeFormatter()
            print(formatter.format(comparison: comparison))
        }
    }
}
