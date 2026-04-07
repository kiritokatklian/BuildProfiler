//
//  Insight.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// An actionable optimization suggestion derived from bundle analysis.
public struct Insight: Codable, Sendable {
    /// Unique identifier (e.g. "duplicate-files").
    public let id: String

    /// Human-readable title (e.g. "Duplicate Files").
    public let title: String

    /// Why it matters and how to fix it.
    public let description: String

    /// Severity level based on potential impact.
    public let severity: InsightSeverity

    /// Estimated bytes recoverable.
    public let savingsBytes: UInt64

    /// Files affected by this insight.
    public let affectedFiles: [InsightFile]
}

/// Severity classification for an insight.
public enum InsightSeverity: String, Codable, Sendable {
    /// Build config issue or > 5% savings.
    case critical

    /// 1–5% savings.
    case warning

    /// < 1% savings.
    case info

    /// No issues found — shown with a checkmark.
    case passing
}

/// A file referenced by an insight.
public struct InsightFile: Codable, Sendable {
    /// Relative path within the bundle.
    public let path: String

    /// Size in bytes.
    public let size: UInt64

    /// Additional context (e.g. "3 copies", "@2x outside catalog").
    public let detail: String?
}
