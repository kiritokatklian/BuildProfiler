//
//  BudgetParser.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Parses human-readable size strings (e.g., "50MB", "1.5GB", "500KB") into byte counts.
public enum BudgetParser: Sendable {
    public enum ParseError: Error, CustomStringConvertible {
        case invalidFormat(String)

        public var description: String {
            switch self {
            case .invalidFormat(let input): "Invalid budget format: '\(input)'. Expected a value like '50MB', '1.5GB', '500KB', or bare bytes."
            }
        }
    }

    /// Parse a budget string into a byte count.
    public static func parse(_ input: String) -> Result<UInt64, ParseError> {
        let trimmed = input.trimmingCharacters(in: .whitespaces).uppercased()

        guard !trimmed.isEmpty else {
            return .failure(.invalidFormat(input))
        }

        // Try to match known suffixes
        let suffixes: [(String, Double)] = [
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1024),
            ("B", 1),
        ]

        for (suffix, multiplier) in suffixes {
            if trimmed.hasSuffix(suffix) {
                let numberStr = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                guard let value = Double(numberStr), value >= 0 else {
                    return .failure(.invalidFormat(input))
                }
                return .success(UInt64(value * multiplier))
            }
        }

        // Bare number — treat as bytes
        if let value = UInt64(trimmed) {
            return .success(value)
        }

        if let value = Double(trimmed), value >= 0 {
            return .success(UInt64(value))
        }

        return .failure(.invalidFormat(input))
    }
}
