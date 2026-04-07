//
//  MachOParser.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Parses Mach-O binaries to extract architecture, segment, and section information.
public struct MachOParser: Sendable {
    // Mach-O magic numbers
    private static let MH_MAGIC_64: UInt32 = 0xFEED_FACF
    private static let MH_CIGAM_64: UInt32 = 0xCFFA_EDFE
    private static let MH_MAGIC: UInt32 = 0xFEED_FACE
    private static let MH_CIGAM: UInt32 = 0xCEFA_EDFE
    private static let FAT_MAGIC: UInt32 = 0xCAFE_BABE
    private static let FAT_CIGAM: UInt32 = 0xBEBA_FECA

    // Load command types
    private static let LC_SEGMENT_64: UInt32 = 0x19
    private static let LC_LOAD_DYLIB: UInt32 = 0x0C
    private static let LC_LOAD_WEAK_DYLIB: UInt32 = 0x8000_0018
    private static let LC_REEXPORT_DYLIB: UInt32 = 0x8000_001F
    private static let LC_LAZY_LOAD_DYLIB: UInt32 = 0x20

    // CPU types
    private static let CPU_TYPE_ARM64: UInt32 = 0x0100_000C
    private static let CPU_TYPE_X86_64: UInt32 = 0x0100_0007
    private static let CPU_TYPE_ARM: UInt32 = 0x0000_000C
    private static let CPU_TYPE_X86: UInt32 = 0x0000_0007

    public enum ParseError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case notMachO(String)
        case invalidFormat(String)

        public var description: String {
            switch self {
            case .fileNotFound(let path): "File not found: \(path)"
            case .notMachO(let path): "Not a Mach-O binary: \(path)"
            case .invalidFormat(let reason): "Invalid Mach-O format: \(reason)"
            }
        }
    }

    /// Parse a Mach-O binary at the given path.
    public static func parse(path: String) throws -> MachOInfo {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let name = (path as NSString).lastPathComponent
        let fileSize = UInt64(data.count)

        guard data.count >= 4 else {
            throw ParseError.notMachO(path)
        }

        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }

        switch magic {
        case self.FAT_MAGIC, self.FAT_CIGAM:
            let slices = try parseFatBinary(data: data, isBigEndian: magic == self.FAT_MAGIC)
            return MachOInfo(name: name, fileSize: fileSize, slices: slices)

        case self.MH_MAGIC_64, self.MH_CIGAM_64:
            let swapped = magic == self.MH_CIGAM_64
            let slice = try parseSingleSlice(data: data, offset: 0, swapped: swapped, is64Bit: true)
            return MachOInfo(name: name, fileSize: fileSize, slices: [slice])

        case self.MH_MAGIC, self.MH_CIGAM:
            let swapped = magic == self.MH_CIGAM
            let slice = try parseSingleSlice(data: data, offset: 0, swapped: swapped, is64Bit: false)
            return MachOInfo(name: name, fileSize: fileSize, slices: [slice])

        default:
            throw ParseError.notMachO(path)
        }
    }

    // MARK: - Fat Binary Parsing
    private static func parseFatBinary(data: Data, isBigEndian: Bool) throws -> [MachOSlice] {
        guard data.count >= 8 else {
            throw ParseError.invalidFormat("Fat header too small")
        }

        // Fat binary headers are always big-endian regardless of host byte order.
        let nfatArch: UInt32 = data.withUnsafeBytes { buf in
            UInt32(bigEndian: buf.load(fromByteOffset: 4, as: UInt32.self))
        }

        guard nfatArch > 0, nfatArch < 256 else {
            throw ParseError.invalidFormat("Unreasonable number of fat architectures: \(nfatArch)")
        }

        var slices: [MachOSlice] = []
        let fatArchSize = 20 // sizeof(fat_arch)

        for i in 0 ..< Int(nfatArch) {
            let archOffset = 8 + i * fatArchSize

            guard archOffset + fatArchSize <= data.count else {
                throw ParseError.invalidFormat("Fat arch entry out of bounds")
            }

            // Fat arch entries are always big-endian
            let (cpuType, offset, size) = data.withUnsafeBytes { buf -> (UInt32, UInt32, UInt32) in
                let ct = UInt32(bigEndian: buf.load(fromByteOffset: archOffset, as: UInt32.self))
                let off = UInt32(bigEndian: buf.load(fromByteOffset: archOffset + 8, as: UInt32.self))
                let sz = UInt32(bigEndian: buf.load(fromByteOffset: archOffset + 12, as: UInt32.self))
                return (ct, off, sz)
            }

            guard Int(offset) + Int(size) <= data.count else {
                throw ParseError.invalidFormat("Fat slice out of bounds")
            }

            let sliceData = data[Int(offset) ..< Int(offset) + Int(size)]

            guard sliceData.count >= 4 else { continue }

            let sliceMagic = sliceData.withUnsafeBytes { $0.load(as: UInt32.self) }
            let is64 = sliceMagic == self.MH_MAGIC_64 || sliceMagic == self.MH_CIGAM_64
            let swapped = sliceMagic == self.MH_CIGAM_64 || sliceMagic == self.MH_CIGAM

            var slice = try parseSingleSlice(data: data, offset: Int(offset), swapped: swapped, is64Bit: is64)

            // Override architecture from fat header's cputype if we got "unknown"
            if slice.architecture == "unknown" {
                slice = MachOSlice(
                    architecture: self.architectureName(for: cpuType),
                    offset: UInt64(offset),
                    size: UInt64(size),
                    segments: slice.segments,
                    dependencies: slice.dependencies
                )
            }

            slices.append(slice)
        }

        return slices
    }

    // MARK: - Single Slice Parsing
    private static func parseSingleSlice(data: Data, offset: Int, swapped: Bool, is64Bit: Bool) throws -> MachOSlice {
        let headerSize = is64Bit ? 32 : 28 // mach_header_64 vs mach_header

        guard offset + headerSize <= data.count else {
            throw ParseError.invalidFormat("Mach-O header out of bounds")
        }

        let (cpuType, ncmds, sizeOfCmds) = data.withUnsafeBytes { buf -> (UInt32, UInt32, UInt32) in
            let ct = buf.load(fromByteOffset: offset + 4, as: UInt32.self)
            let nc = buf.load(fromByteOffset: offset + 16, as: UInt32.self)
            let sc = buf.load(fromByteOffset: offset + 20, as: UInt32.self)
            if swapped {
                return (ct.byteSwapped, nc.byteSwapped, sc.byteSwapped)
            }
            return (ct, nc, sc)
        }

        let arch = self.architectureName(for: cpuType)
        var segments: [MachOSegment] = []
        var dependencies: [DylibDependency] = []
        var cmdOffset = offset + headerSize

        guard cmdOffset + Int(sizeOfCmds) <= data.count else {
            throw ParseError.invalidFormat("Load commands extend beyond file")
        }

        for _ in 0 ..< ncmds {
            guard cmdOffset + 8 <= data.count else { break }

            let (cmd, cmdSize) = data.withUnsafeBytes { buf -> (UInt32, UInt32) in
                let c = buf.load(fromByteOffset: cmdOffset, as: UInt32.self)
                let s = buf.load(fromByteOffset: cmdOffset + 4, as: UInt32.self)
                if swapped {
                    return (c.byteSwapped, s.byteSwapped)
                }
                return (c, s)
            }

            guard cmdSize >= 8 && cmdOffset + Int(cmdSize) <= data.count else { break }

            if cmd == self.LC_SEGMENT_64 && is64Bit {
                if let segment = parseSegment64(data: data, offset: cmdOffset, swapped: swapped) {
                    segments.append(segment)
                }
            } else if let dep = parseDylibCommand(data: data, offset: cmdOffset, cmdSize: Int(cmdSize), cmd: cmd, swapped: swapped) {
                dependencies.append(dep)
            }

            cmdOffset += Int(cmdSize)
        }

        let sliceSize = UInt64(headerSize) + UInt64(sizeOfCmds) + segments.reduce(0) { $0 + $1.fileSize }

        return MachOSlice(
            architecture: arch,
            offset: UInt64(offset),
            size: sliceSize,
            segments: segments,
            dependencies: dependencies
        )
    }

    // MARK: - Segment Parsing
    private static func parseSegment64(data: Data, offset: Int, swapped: Bool) -> MachOSegment? {
        // LC_SEGMENT_64 layout:
        // 0: cmd (4), 4: cmdsize (4), 8: segname (16), 24: vmaddr (8),
        // 32: vmsize (8), 40: fileoff (8), 48: filesize (8), 56: maxprot (4),
        // 60: initprot (4), 64: nsects (4), 68: flags (4)
        let segmentHeaderSize = 72
        guard offset + segmentHeaderSize <= data.count else { return nil }

        let segName = self.readSegmentName(data: data, offset: offset + 8, length: 16)

        let (vmSize, fileSize, nsects) = data.withUnsafeBytes { buf -> (UInt64, UInt64, UInt32) in
            let vm = buf.load(fromByteOffset: offset + 32, as: UInt64.self)
            let fs = buf.load(fromByteOffset: offset + 48, as: UInt64.self)
            let ns = buf.load(fromByteOffset: offset + 64, as: UInt32.self)
            if swapped {
                return (vm.byteSwapped, fs.byteSwapped, ns.byteSwapped)
            }
            return (vm, fs, ns)
        }

        // Parse sections
        let sectionSize = 80 // sizeof(section_64)
        var sections: [MachOSection] = []
        var sectOffset = offset + segmentHeaderSize

        for _ in 0 ..< nsects {
            guard sectOffset + sectionSize <= data.count else { break }

            let sectName = self.readSegmentName(data: data, offset: sectOffset, length: 16)
            let sectSegName = self.readSegmentName(data: data, offset: sectOffset + 16, length: 16)

            let (sectSize, sectFileOffset) = data.withUnsafeBytes { buf -> (UInt64, UInt32) in
                let s = buf.load(fromByteOffset: sectOffset + 40, as: UInt64.self)
                let fo = buf.load(fromByteOffset: sectOffset + 48, as: UInt32.self)
                return swapped ? (s.byteSwapped, fo.byteSwapped) : (s, fo)
            }

            sections.append(MachOSection(name: sectName, segmentName: sectSegName, size: sectSize, fileOffset: UInt64(sectFileOffset)))
            sectOffset += sectionSize
        }

        return MachOSegment(name: segName, fileSize: fileSize, vmSize: vmSize, sections: sections)
    }

    // MARK: - Dylib Command Parsing
    /// Parse a dylib load command (`LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, `LC_REEXPORT_DYLIB`, `LC_LAZY_LOAD_DYLIB`).
    private static func parseDylibCommand(data: Data, offset: Int, cmdSize: Int, cmd: UInt32, swapped: Bool) -> DylibDependency? {
        let dylibType: DylibType
        switch cmd {
        case self.LC_LOAD_DYLIB: dylibType = .load
        case self.LC_LOAD_WEAK_DYLIB: dylibType = .weak
        case self.LC_REEXPORT_DYLIB: dylibType = .reexport
        case self.LC_LAZY_LOAD_DYLIB: dylibType = .lazy
        default: return nil
        }

        // dylib_command layout:
        // 0: cmd (4), 4: cmdsize (4),
        // 8: name offset (4), 12: timestamp (4), 16: current_version (4), 20: compat_version (4)
        guard cmdSize >= 24 else { return nil }

        let (nameOffset, currentVersionRaw, compatVersionRaw) = data.withUnsafeBytes { buf -> (UInt32, UInt32, UInt32) in
            let no = buf.load(fromByteOffset: offset + 8, as: UInt32.self)
            let cv = buf.load(fromByteOffset: offset + 16, as: UInt32.self)
            let cpv = buf.load(fromByteOffset: offset + 20, as: UInt32.self)
            if swapped {
                return (no.byteSwapped, cv.byteSwapped, cpv.byteSwapped)
            }
            return (no, cv, cpv)
        }

        // Extract null-terminated name string
        let nameStart = offset + Int(nameOffset)
        guard nameStart < offset + cmdSize else { return nil }
        let nameLength = offset + cmdSize - nameStart
        let name = self.readSegmentName(data: data, offset: nameStart, length: nameLength)

        guard !name.isEmpty else { return nil }

        return DylibDependency(
            name: name,
            type: dylibType,
            currentVersion: DylibVersion.from(encoded: currentVersionRaw),
            compatibilityVersion: DylibVersion.from(encoded: compatVersionRaw)
        )
    }

    // MARK: - Helpers
    private static func readSegmentName(data: Data, offset: Int, length: Int) -> String {
        guard offset + length <= data.count else { return "" }
        let nameData = data[offset ..< offset + length]
        let bytes = Array(nameData)
        // Find null terminator
        let endIndex = bytes.firstIndex(of: 0) ?? length
        return String(bytes: bytes[0 ..< endIndex], encoding: .utf8) ?? ""
    }

    private static func architectureName(for cpuType: UInt32) -> String {
        switch cpuType {
        case self.CPU_TYPE_ARM64: "arm64"
        case self.CPU_TYPE_X86_64: "x86_64"
        case self.CPU_TYPE_ARM: "armv7"
        case self.CPU_TYPE_X86: "i386"
        default: "unknown(\(cpuType))"
        }
    }
}
