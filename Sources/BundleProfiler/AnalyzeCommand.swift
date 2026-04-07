//
//  AnalyzeCommand.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import ArgumentParser
import BundleProfilerKit
import Foundation

struct AnalyzeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze an .app bundle or .ipa file.",
        discussion: """
        Produces a full size report: category breakdown, Mach-O segments and \
        linked dylibs, per-architecture thinning estimates, embedded frameworks, \
        asset catalogs, and duplicate resources.
        """
    )

    @Argument(help: "Path to the .app bundle or .ipa file.")
    var path: String

    @Option(name: .long, help: "Output format: tree (default), json, html, or markdown.")
    var format: OutputFormat = .tree

    @Option(name: .shortAndLong, help: "Write output to a file instead of stdout.")
    var output: String?

    @Option(name: .long, help: "Show top N largest files.")
    var top: Int?

    @Flag(name: .long, inversion: .prefixedNo, help: "Analyze Mach-O binaries.")
    var machO: Bool = true

    @Flag(name: .long, inversion: .prefixedNo, help: "Detect duplicate resources.")
    var duplicates: Bool = true

    func run() throws {
        let resolvedPath = resolvePath(path)
        let options = BundleAnalyzer.Options(
            analyzeMachO: self.machO,
            detectDuplicates: self.duplicates,
            topN: self.top
        )

        let analyzer = BundleAnalyzer(options: options)
        let result = try analyzer.analyze(path: resolvedPath)

        let content: String
        switch self.format {
        case .tree:
            let formatter = TreeFormatter()
            content = formatter.format(bundle: result, topN: self.top)
        case .json:
            let formatter = JSONFormatter()
            content = try formatter.format(bundle: result)
        case .html:
            let formatter = HTMLFormatter()
            content = try formatter.format(bundle: result)
        case .markdown:
            let formatter = MarkdownFormatter()
            content = formatter.format(bundle: result)
        }

        try writeOutput(content, to: self.output)
    }
}
