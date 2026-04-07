//
//  BudgetResult.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Result of checking a bundle against a size budget.
public struct BudgetResult: Codable, Sendable {
    /// Bundle name.
    public let bundleName: String

    /// Actual total size in bytes.
    public let totalSize: UInt64

    /// Budget threshold in bytes.
    public let budget: UInt64

    /// Whether the bundle exceeds the budget.
    public var isOverBudget: Bool {
        totalSize > budget
    }

    /// Signed delta from budget (positive = over budget).
    public var delta: Int64 {
        Int64(totalSize) - Int64(budget)
    }

    /// Size breakdown by category.
    public let categoryBreakdown: [FileCategory: UInt64]

    public init(bundleName: String, totalSize: UInt64, budget: UInt64, categoryBreakdown: [FileCategory: UInt64]) {
        self.bundleName = bundleName
        self.totalSize = totalSize
        self.budget = budget
        self.categoryBreakdown = categoryBreakdown
    }
}
