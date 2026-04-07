//
//  MachOStringExtractor.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Extracts string constants from Mach-O binary sections for unused resource detection.
public struct MachOStringExtractor: Sendable {
    /// Sections that contain string references to resources.
    private static let targetSections: Set<String> = [
        "__cstring",
        "__objc_methname",
        "__objc_classname",
        "__ustring",
        "__swift5_reflstr",
    ]

    /// Extract all null-terminated C strings from relevant sections of a Mach-O binary.
    public static func extractStrings(binaryPath: String, machOInfo: MachOInfo) -> Set<String> {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: binaryPath), options: .mappedIfSafe) else {
            return []
        }

        var strings: Set<String> = []

        for slice in machOInfo.slices {
            let sliceOffset = machOInfo.slices.count > 1 ? Int(slice.offset) : 0

            for segment in slice.segments {
                for section in segment.sections {
                    guard Self.targetSections.contains(section.name) else { continue }
                    guard section.size > 0, section.fileOffset > 0 else { continue }

                    let offset = sliceOffset > 0 ? Int(section.fileOffset) : Int(section.fileOffset)
                    let size = Int(section.size)

                    guard offset >= 0, offset + size <= data.count else { continue }

                    if section.name == "__ustring" {
                        strings.formUnion(extractUTF16Strings(from: data, offset: offset, size: size))
                    } else {
                        strings.formUnion(extractCStrings(from: data, offset: offset, size: size))
                    }
                }
            }

            // Only process first slice to avoid duplicates
            break
        }

        return strings
    }

    /// Extract null-terminated C strings from a region of data.
    private static func extractCStrings(from data: Data, offset: Int, size: Int) -> Set<String> {
        var result: Set<String> = []
        let endOffset = min(offset + size, data.count)

        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var start = offset

            for i in offset ..< endOffset {
                if bytes[i] == 0 {
                    let length = i - start
                    if length > 0, length < 1024 {
                        if let str = String(bytes: bytes[start ..< i], encoding: .utf8), !str.isEmpty {
                            result.insert(str)
                        }
                    }
                    start = i + 1
                }
            }
        }

        return result
    }

    /// Extract null-terminated UTF-16 strings from a __ustring section.
    private static func extractUTF16Strings(from data: Data, offset: Int, size: Int) -> Set<String> {
        var result: Set<String> = []
        let endOffset = min(offset + size, data.count)

        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var start = offset
            var i = offset

            while i + 1 < endOffset {
                let lo = bytes[i]
                let hi = bytes[i + 1]
                if lo == 0, hi == 0 {
                    let length = i - start
                    if length > 0, length < 2048 {
                        let subdata = Data(bytes: bytes.baseAddress!.advanced(by: start), count: length)
                        if let str = String(data: subdata, encoding: .utf16LittleEndian), !str.isEmpty {
                            result.insert(str)
                        }
                    }
                    start = i + 2
                }
                i += 2
            }
        }

        return result
    }
}
