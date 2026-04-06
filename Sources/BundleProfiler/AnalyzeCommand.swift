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
        abstract: "Analyze an .app bundle or .ipa file."
    )

    @Argument(help: "Path to the .app bundle or .ipa file.")
    var path: String

    @Option(name: .long, help: "Output format: tree (default) or json.")
    var format: OutputFormat = .tree

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

        switch self.format {
        case .tree:
            let formatter = TreeFormatter()
            print(formatter.format(bundle: result, topN: self.top))
        case .json:
            let formatter = JSONFormatter()
            let output = try formatter.format(bundle: result)
            print(output)
        }
    }
}

enum OutputFormat: String, ExpressibleByArgument {
    case tree
    case json
}

private func resolvePath(_ path: String) -> String {
    if path.hasPrefix("/") || path.hasPrefix("~") {
        return (path as NSString).expandingTildeInPath
    }
    return FileManager.default.currentDirectoryPath + "/" + path
}
