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
        abstract: "Analyze iOS and macOS app bundle sizes.",
        discussion: """
        Drill into .app bundles and .ipa files to see exactly where space goes: \
        file categories, Mach-O segments, linked dylibs, per-framework costs, \
        duplicate resources, asset catalogs, and per-architecture thinning estimates.

        Output as a human-readable tree, JSON, Markdown (for PR comments), \
        or a self-contained HTML treemap.

        Use 'check' in CI to enforce a size budget with a non-zero exit code.
        """,
        version: "1.1.0",
        subcommands: [AnalyzeCommand.self, CompareCommand.self, CheckCommand.self],
        defaultSubcommand: AnalyzeCommand.self
    )
}
