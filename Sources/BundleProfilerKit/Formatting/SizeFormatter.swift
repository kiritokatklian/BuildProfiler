//
//  SizeFormatter.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Formats byte sizes into human-readable strings.
public enum SizeFormatter: Sendable {
    private static let units: [(String, Double)] = [
        ("GB", 1_073_741_824),
        ("MB", 1_048_576),
        ("KB", 1024),
        ("B", 1),
    ]

    /// Format a byte count as a human-readable string (e.g., "12.4 MB").
    public static func format(_ bytes: UInt64) -> String {
        let value = Double(bytes)

        for (unit, threshold) in self.units {
            if value >= threshold {
                let formatted = value / threshold
                if formatted >= 100 || unit == "B" {
                    return String(format: "%.0f %@", formatted, unit)
                } else if formatted >= 10 {
                    return String(format: "%.1f %@", formatted, unit)
                } else {
                    return String(format: "%.2f %@", formatted, unit)
                }
            }
        }

        return "0 B"
    }

    /// Format a signed byte delta (e.g., "+340 KB", "-1.2 MB").
    public static func formatDelta(_ bytes: Int64) -> String {
        let prefix = bytes > 0 ? "+" : bytes < 0 ? "-" : "+"
        let absBytes = UInt64(bytes < 0 ? -bytes : bytes)
        return "\(prefix)\(self.format(absBytes))"
    }

    /// Format a percentage (e.g., "25.7%").
    public static func formatPercentage(_ fraction: Double) -> String {
        if fraction >= 0.1 {
            return String(format: "%.1f%%", fraction * 100)
        } else if fraction >= 0.01 {
            return String(format: "%.2f%%", fraction * 100)
        } else {
            return String(format: "%.1f%%", fraction * 100)
        }
    }

    /// Pad a size string to a consistent width for alignment.
    public static func padded(_ bytes: UInt64, width: Int = 10) -> String {
        let str = self.format(bytes)
        return str.count < width
            ? String(repeating: " ", count: width - str.count) + str
            : str
    }

    /// Pad a delta string to a consistent width for alignment.
    public static func paddedDelta(_ bytes: Int64, width: Int = 10) -> String {
        let str = self.formatDelta(bytes)
        return str.count < width
            ? String(repeating: " ", count: width - str.count) + str
            : str
    }
}
