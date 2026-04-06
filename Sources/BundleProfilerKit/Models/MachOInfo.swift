//
//  MachOInfo.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Information about a Mach-O binary.
public struct MachOInfo: Codable, Sendable {
    /// Name of the binary (e.g., "MyApp", "Alamofire").
    public let name: String

    /// Total file size on disk.
    public let fileSize: UInt64

    /// Individual architecture slices.
    public let slices: [MachOSlice]

    public init(name: String, fileSize: UInt64, slices: [MachOSlice]) {
        self.name = name
        self.fileSize = fileSize
        self.slices = slices
    }
}

/// A single architecture slice within a Mach-O binary.
public struct MachOSlice: Codable, Sendable {
    /// Architecture name (e.g., "arm64", "x86_64").
    public let architecture: String

    /// Offset within the file.
    public let offset: UInt64

    /// Size of this slice.
    public let size: UInt64

    /// Segments within this slice.
    public let segments: [MachOSegment]

    public init(architecture: String, offset: UInt64, size: UInt64, segments: [MachOSegment]) {
        self.architecture = architecture
        self.offset = offset
        self.size = size
        self.segments = segments
    }
}

/// A segment within a Mach-O slice (e.g., __TEXT, __DATA, __LINKEDIT).
public struct MachOSegment: Codable, Sendable {
    /// Segment name.
    public let name: String

    /// Size in the file.
    public let fileSize: UInt64

    /// Size in virtual memory.
    public let vmSize: UInt64

    /// Sections within this segment.
    public let sections: [MachOSection]

    public init(name: String, fileSize: UInt64, vmSize: UInt64, sections: [MachOSection]) {
        self.name = name
        self.fileSize = fileSize
        self.vmSize = vmSize
        self.sections = sections
    }
}

/// A section within a Mach-O segment (e.g., __text, __objc_methname).
public struct MachOSection: Codable, Sendable {
    /// Section name.
    public let name: String

    /// Segment this section belongs to.
    public let segmentName: String

    /// Size in bytes.
    public let size: UInt64

    public init(name: String, segmentName: String, size: UInt64) {
        self.name = name
        self.segmentName = segmentName
        self.size = size
    }
}
