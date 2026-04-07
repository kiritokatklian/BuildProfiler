//
//  ThinningSimulator.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Estimates per-device download sizes by simulating app thinning per architecture.
public struct ThinningSimulator: Sendable {
    public init() {}

    /// Simulate app thinning for the given bundle.
    public func simulate(bundle: BundleInfo) -> ThinningReport {
        // Collect all MachO slices from main executable + frameworks
        var allMachOs: [MachOInfo] = []
        if let mainExec = bundle.mainExecutable {
            allMachOs.append(mainExec)
        }
        for framework in bundle.frameworks {
            if let machO = framework.machOInfo {
                allMachOs.append(machO)
            }
        }

        guard !allMachOs.isEmpty else {
            return ThinningReport(bundleName: bundle.bundleName, estimates: [])
        }

        // Collect all unique architectures
        var architectures: [String] = []
        for machO in allMachOs {
            for slice in machO.slices {
                if !architectures.contains(slice.architecture) {
                    architectures.append(slice.architecture)
                }
            }
        }

        // Calculate total fat binary file sizes (all slices combined)
        let totalFatBinaryFileSize: UInt64 = allMachOs.reduce(0) { $0 + $1.fileSize }

        // Resource size = everything that isn't a fat binary
        let resourceSize = bundle.totalSize >= totalFatBinaryFileSize
            ? bundle.totalSize - totalFatBinaryFileSize
            : bundle.totalSize

        // Per-architecture estimates
        let estimates = architectures.map { arch -> ThinningEstimate in
            var binarySize: UInt64 = 0
            for machO in allMachOs {
                if let slice = machO.slices.first(where: { $0.architecture == arch }) {
                    binarySize += slice.size
                }
            }

            return ThinningEstimate(
                architecture: arch,
                estimatedSize: binarySize + resourceSize,
                binarySize: binarySize,
                resourceSize: resourceSize
            )
        }

        return ThinningReport(bundleName: bundle.bundleName, estimates: estimates)
    }
}
