//
//  CheckCommand.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import ArgumentParser
import BundleProfilerKit
import Foundation

struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check bundle size against a budget. Exits non-zero if over budget.",
        discussion: """
        CI gate: analyzes the bundle and compares its total size to the given \
        budget. Exits 0 if within budget, 1 if over. Use --format markdown to \
        produce a table suitable for a GitHub PR comment.

        Budget accepts human-readable sizes: '50MB', '1.5GB', '500KB', or \
        bare byte counts.
        """
    )

    @Argument(help: "Path to the .app bundle or .ipa file.")
    var path: String

    @Option(name: .long, help: "Size budget (e.g., '50MB', '1.5GB', '500KB').")
    var budget: String

    @Option(name: .long, help: "Output format: tree (default), json, or markdown.")
    var format: OutputFormat = .tree

    @Option(name: .shortAndLong, help: "Write output to a file instead of stdout.")
    var output: String?

    func run() throws {
        let resolvedPath = resolvePath(path)

        let budgetBytes: UInt64
        switch BudgetParser.parse(self.budget) {
        case .success(let bytes):
            budgetBytes = bytes
        case .failure(let error):
            throw ValidationError(error.description)
        }

        let analyzer = BundleAnalyzer()
        let bundle = try analyzer.analyze(path: resolvedPath)

        let result = BudgetResult(
            bundleName: bundle.bundleName,
            totalSize: bundle.totalSize,
            budget: budgetBytes,
            categoryBreakdown: bundle.categoryBreakdown
        )

        let content: String
        switch self.format {
        case .tree:
            content = self.treeOutput(result)
        case .json:
            content = try self.jsonOutput(result)
        case .markdown:
            let formatter = MarkdownFormatter()
            content = formatter.format(budget: result)
        case .html:
            content = self.treeOutput(result)
        }

        try writeOutput(content, to: self.output)

        if result.isOverBudget {
            throw ExitCode(1)
        }
    }

    private func treeOutput(_ result: BudgetResult) -> String {
        var lines: [String] = []
        let status = result.isOverBudget ? "OVER BUDGET" : "UNDER BUDGET"
        lines.append("BUNDLE SIZE CHECK: \(status)")
        lines.append(String(repeating: "=", count: 60))
        lines.append("  Bundle:     \(result.bundleName)")
        lines.append("  Total Size: \(SizeFormatter.format(result.totalSize))")
        lines.append("  Budget:     \(SizeFormatter.format(result.budget))")
        lines.append("  Delta:      \(SizeFormatter.formatDelta(result.delta))")
        lines.append("")

        let sorted = result.categoryBreakdown.sorted { $0.value > $1.value }
        if !sorted.isEmpty {
            lines.append("CATEGORY BREAKDOWN")
            lines.append(String(repeating: "-", count: 60))
            for (category, size) in sorted {
                let name = category.displayName.padding(toLength: 22, withPad: " ", startingAt: 0)
                let sizeStr = SizeFormatter.padded(size)
                let pct = result.totalSize > 0
                    ? SizeFormatter.formatPercentage(Double(size) / Double(result.totalSize))
                    : "0.0%"
                lines.append("  \(name) \(sizeStr)  \(pct)")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func jsonOutput(_ result: BudgetResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
