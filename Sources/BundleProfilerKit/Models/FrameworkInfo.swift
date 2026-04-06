//
//  FrameworkInfo.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Breakdown of a single embedded framework.
public struct FrameworkInfo: Codable, Sendable {
    /// Framework name (e.g., "Alamofire").
    public let name: String

    /// Total size of the .framework directory.
    public let totalSize: UInt64

    /// Size of the main binary.
    public let binarySize: UInt64

    /// Size of non-binary resources.
    public let resourceSize: UInt64

    /// Size of code signature files.
    public let codeSignatureSize: UInt64

    /// Mach-O analysis of the framework binary, if available.
    public let machOInfo: MachOInfo?

    public init(
        name: String,
        totalSize: UInt64,
        binarySize: UInt64,
        resourceSize: UInt64,
        codeSignatureSize: UInt64,
        machOInfo: MachOInfo?
    ) {
        self.name = name
        self.totalSize = totalSize
        self.binarySize = binarySize
        self.resourceSize = resourceSize
        self.codeSignatureSize = codeSignatureSize
        self.machOInfo = machOInfo
    }
}
