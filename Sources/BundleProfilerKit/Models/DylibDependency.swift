//
//  DylibDependency.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Type of dylib linkage.
public enum DylibType: String, Codable, Sendable {
    case load
    case weak
    case reexport
    case lazy
}

/// Decoded Mach-O dylib version (major.minor.patch).
public struct DylibVersion: Codable, Sendable, Equatable, CustomStringConvertible {
    public let major: UInt16
    public let minor: UInt8
    public let patch: UInt8

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    /// Decode from the Mach-O encoded 32-bit version format.
    public static func from(encoded value: UInt32) -> DylibVersion {
        DylibVersion(
            major: UInt16(value >> 16),
            minor: UInt8((value >> 8) & 0xFF),
            patch: UInt8(value & 0xFF)
        )
    }
}

/// A linked dynamic library dependency parsed from a Mach-O binary.
public struct DylibDependency: Codable, Sendable {
    /// Install name / path of the dylib (e.g., "/usr/lib/libSystem.B.dylib").
    public let name: String

    /// Linkage type.
    public let type: DylibType

    /// Current version of the dylib.
    public let currentVersion: DylibVersion

    /// Compatibility version of the dylib.
    public let compatibilityVersion: DylibVersion

    public init(name: String, type: DylibType, currentVersion: DylibVersion, compatibilityVersion: DylibVersion) {
        self.name = name
        self.type = type
        self.currentVersion = currentVersion
        self.compatibilityVersion = compatibilityVersion
    }
}
