//
//  JSONFormatter.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Formats analysis results as pretty-printed JSON.
public struct JSONFormatter: Sendable {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public init() {}

    /// Format a BundleInfo as JSON.
    public func format(bundle: BundleInfo) throws -> String {
        let data = try Self.encoder.encode(bundle)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Format a ComparisonResult as JSON.
    public func format(comparison: ComparisonResult) throws -> String {
        let data = try Self.encoder.encode(comparison)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
