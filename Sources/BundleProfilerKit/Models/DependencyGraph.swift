//
//  DependencyGraph.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// A directed graph of binary dependencies within the app bundle.
public struct DependencyGraph: Codable, Sendable {
    /// All binaries (nodes) in the graph.
    public let nodes: [DependencyNode]

    /// Directed edges representing dependency links.
    public let edges: [DependencyEdge]

    /// Name of the root node (main executable).
    public let rootNode: String

    /// Maximum depth of the dependency tree.
    public let maxDepth: Int

    /// The dependency chain with the largest cumulative binary size.
    public let heaviestChain: DependencyChain

    public init(
        nodes: [DependencyNode],
        edges: [DependencyEdge],
        rootNode: String,
        maxDepth: Int,
        heaviestChain: DependencyChain
    ) {
        self.nodes = nodes
        self.edges = edges
        self.rootNode = rootNode
        self.maxDepth = maxDepth
        self.heaviestChain = heaviestChain
    }
}

/// A binary node in the dependency graph.
public struct DependencyNode: Codable, Sendable {
    /// Display name of the binary.
    public let name: String

    /// Size of the binary on disk.
    public let binarySize: UInt64

    /// Whether this is a system-provided library.
    public let isSystemLibrary: Bool

    /// Classification of this node.
    public let nodeType: DependencyNodeType

    public init(name: String, binarySize: UInt64, isSystemLibrary: Bool, nodeType: DependencyNodeType) {
        self.name = name
        self.binarySize = binarySize
        self.isSystemLibrary = isSystemLibrary
        self.nodeType = nodeType
    }
}

/// Classification of a dependency node.
public enum DependencyNodeType: String, Codable, Sendable {
    case mainExecutable
    case embeddedFramework
    case systemDylib
    case spmPackage
}

/// A directed edge in the dependency graph.
public struct DependencyEdge: Codable, Sendable {
    /// Source binary name.
    public let from: String

    /// Target binary name.
    public let to: String

    /// How the dependency is linked.
    public let linkType: DylibType

    /// Whether this edge is redundant (target reachable via another path).
    public let isRedundant: Bool

    public init(from: String, to: String, linkType: DylibType, isRedundant: Bool) {
        self.from = from
        self.to = to
        self.linkType = linkType
        self.isRedundant = isRedundant
    }
}

/// A chain of dependencies with cumulative size.
public struct DependencyChain: Codable, Sendable {
    /// Ordered list of binary names in the chain.
    public let path: [String]

    /// Sum of binary sizes along the chain.
    public let totalSize: UInt64

    public init(path: [String], totalSize: UInt64) {
        self.path = path
        self.totalSize = totalSize
    }
}
