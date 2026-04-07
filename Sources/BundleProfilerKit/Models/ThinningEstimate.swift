//
//  ThinningEstimate.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Estimated per-device download size for a single architecture.
public struct ThinningEstimate: Codable, Sendable {
    /// Architecture name (e.g., "arm64").
    public let architecture: String

    /// Estimated total download size for this architecture.
    public let estimatedSize: UInt64

    /// Combined binary size for this architecture across all Mach-O binaries.
    public let binarySize: UInt64

    /// Non-binary resource size (shared across all architectures).
    public let resourceSize: UInt64

    public init(architecture: String, estimatedSize: UInt64, binarySize: UInt64, resourceSize: UInt64) {
        self.architecture = architecture
        self.estimatedSize = estimatedSize
        self.binarySize = binarySize
        self.resourceSize = resourceSize
    }
}

/// App thinning simulation report for a bundle.
public struct ThinningReport: Codable, Sendable {
    /// Bundle name.
    public let bundleName: String

    /// Per-architecture estimates.
    public let estimates: [ThinningEstimate]

    public init(bundleName: String, estimates: [ThinningEstimate]) {
        self.bundleName = bundleName
        self.estimates = estimates
    }
}
