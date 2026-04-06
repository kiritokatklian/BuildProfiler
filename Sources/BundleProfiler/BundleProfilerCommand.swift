//
//  BundleProfilerCommand.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import ArgumentParser

@main
struct BundleProfilerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bundle-profiler",
        abstract: "Analyze iOS app bundle sizes.",
        version: "1.0.0",
        subcommands: [AnalyzeCommand.self, CompareCommand.self],
        defaultSubcommand: AnalyzeCommand.self
    )
}
