//
//  DependencyGraphBuilder.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 07/04/2026.
//  MIT
//

import Foundation

/// Builds a dependency graph from already-parsed Mach-O data. No additional file I/O.
public struct DependencyGraphBuilder: Sendable {
    /// Build a dependency graph from the main executable, embedded frameworks, and SPM packages.
    /// Returns nil if no Mach-O data is available.
    public static func build(
        mainExecutable: MachOInfo?,
        frameworks: [FrameworkInfo],
        spmPackages: [SPMPackageInfo] = []
    ) -> DependencyGraph? {
        guard let main = mainExecutable else { return nil }

        // Collect all binaries: main + frameworks with MachO info
        var binaryMap: [String: (machO: MachOInfo, size: UInt64, type: DependencyNodeType)] = [:]
        binaryMap[main.name] = (main, main.fileSize, .mainExecutable)

        for fw in frameworks {
            if let machO = fw.machOInfo {
                binaryMap[fw.name] = (machO, machO.fileSize, .embeddedFramework)
            }
        }

        // Track which SPM packages have dynamic frameworks (to avoid duplicate edges)
        let spmDynamicNames = Set(spmPackages.compactMap { $0.dynamicFramework?.name })

        // Build adjacency list from first slice's dependencies
        var adjacency: [String: [(target: String, linkType: DylibType)]] = [:]
        var allSystemLibs: Set<String> = []

        for (binaryName, info) in binaryMap {
            guard let slice = info.machO.slices.first else { continue }

            var deps: [(target: String, linkType: DylibType)] = []
            for dep in slice.dependencies {
                let libName = extractLibraryName(from: dep.name)
                let isSystem = isSystemLibrary(dep.name)

                if isSystem {
                    allSystemLibs.insert(libName)
                }

                deps.append((libName, dep.type))
            }
            adjacency[binaryName] = deps
        }

        // Add SPM packages as virtual edges from the main executable
        for pkg in spmPackages {
            // Skip if this SPM package already appears as a dynamic framework edge
            if spmDynamicNames.contains(pkg.name) { continue }

            // Add edge from main executable to SPM package
            adjacency[main.name, default: []].append((pkg.name, .load))
        }

        // Build nodes
        var nodes: [DependencyNode] = []
        nodes.append(DependencyNode(
            name: main.name,
            binarySize: main.fileSize,
            isSystemLibrary: false,
            nodeType: .mainExecutable
        ))

        for fw in frameworks {
            nodes.append(DependencyNode(
                name: fw.name,
                binarySize: fw.machOInfo?.fileSize ?? UInt64(fw.binarySize),
                isSystemLibrary: false,
                nodeType: .embeddedFramework
            ))
        }

        // Add SPM package nodes (skip those already represented as embedded frameworks)
        let frameworkNames = Set(frameworks.map(\.name))
        for pkg in spmPackages where !frameworkNames.contains(pkg.name) {
            // For SPM packages with a dynamic framework, use the framework size.
            // For statically linked packages, code is embedded in the main binary
            // and can't be attributed — show 0 to avoid misleading numbers.
            let size: UInt64 = pkg.dynamicFramework?.totalSize ?? 0
            nodes.append(DependencyNode(
                name: pkg.name,
                binarySize: size,
                isSystemLibrary: false,
                nodeType: .spmPackage
            ))
        }

        for lib in allSystemLibs.sorted() {
            nodes.append(DependencyNode(
                name: lib,
                binarySize: 0,
                isSystemLibrary: true,
                nodeType: .systemDylib
            ))
        }

        // Build edges and detect redundancy via BFS
        let reachability = buildReachability(adjacency: adjacency)
        var edges: [DependencyEdge] = []

        for (from, deps) in adjacency {
            for dep in deps {
                let isRedundant = isEdgeRedundant(
                    from: from,
                    to: dep.target,
                    adjacency: adjacency,
                    reachability: reachability
                )

                edges.append(DependencyEdge(
                    from: from,
                    to: dep.target,
                    linkType: dep.linkType,
                    isRedundant: isRedundant
                ))
            }
        }

        // Calculate max depth and heaviest chain via DFS (non-system nodes only)
        var nonSystemSizes: [String: UInt64] = [:]
        for (key, value) in binaryMap {
            nonSystemSizes[key] = value.size
        }
        for pkg in spmPackages where !frameworkNames.contains(pkg.name) {
            nonSystemSizes[pkg.name] = pkg.dynamicFramework?.totalSize ?? 0
        }

        let (maxDepth, heaviestChain) = findHeaviestChain(
            root: main.name,
            adjacency: adjacency,
            sizes: nonSystemSizes
        )

        return DependencyGraph(
            nodes: nodes,
            edges: edges.sorted { $0.from < $1.from },
            rootNode: main.name,
            maxDepth: maxDepth,
            heaviestChain: heaviestChain
        )
    }

    // MARK: - Library Name Extraction
    /// Extract the short library name from an install path.
    /// e.g. "@rpath/Alamofire.framework/Alamofire" -> "Alamofire"
    /// e.g. "/usr/lib/libSystem.B.dylib" -> "libSystem.B"
    private static func extractLibraryName(from installName: String) -> String {
        let components = installName.split(separator: "/").map(String.init)
        guard let last = components.last else { return installName }

        // Framework paths: look for X.framework/X pattern
        if let frameworkIdx = components.firstIndex(where: { $0.hasSuffix(".framework") }) {
            let fwName = String(components[frameworkIdx].dropLast(".framework".count))
            return fwName
        }

        // Dylib: strip .dylib extension
        if last.hasSuffix(".dylib") {
            return String(last.dropLast(".dylib".count))
        }

        return last
    }

    /// Determine if a dependency path points to a system library.
    private static func isSystemLibrary(_ path: String) -> Bool {
        path.hasPrefix("/usr/lib/") ||
        path.hasPrefix("/System/") ||
        path.hasPrefix("@rpath/libswift") // Swift runtime libs
    }

    // MARK: - Reachability / Redundancy Detection
    /// Build transitive reachability sets for each node via BFS.
    private static func buildReachability(
        adjacency: [String: [(target: String, linkType: DylibType)]]
    ) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]

        for source in adjacency.keys {
            var visited: Set<String> = []
            var queue: [String] = []

            for dep in adjacency[source] ?? [] {
                queue.append(dep.target)
            }

            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard visited.insert(current).inserted else { continue }

                for dep in adjacency[current] ?? [] {
                    if !visited.contains(dep.target) {
                        queue.append(dep.target)
                    }
                }
            }

            result[source] = visited
        }

        return result
    }

    /// An edge A->B is redundant if B is reachable from A through another direct dependency.
    private static func isEdgeRedundant(
        from: String,
        to: String,
        adjacency: [String: [(target: String, linkType: DylibType)]],
        reachability: [String: Set<String>]
    ) -> Bool {
        let directDeps = adjacency[from] ?? []
        for dep in directDeps where dep.target != to {
            if reachability[dep.target]?.contains(to) == true {
                return true
            }
        }
        return false
    }

    // MARK: - Heaviest Chain (DFS)
    /// Find the heaviest dependency chain and max depth via DFS through non-system nodes.
    private static func findHeaviestChain(
        root: String,
        adjacency: [String: [(target: String, linkType: DylibType)]],
        sizes: [String: UInt64]
    ) -> (maxDepth: Int, chain: DependencyChain) {
        var bestPath: [String] = [root]
        var bestSize: UInt64 = sizes[root] ?? 0
        var maxDepth = 0

        func dfs(node: String, path: [String], cumulativeSize: UInt64, depth: Int, visited: inout Set<String>) {
            maxDepth = max(maxDepth, depth)

            if cumulativeSize > bestSize || (cumulativeSize == bestSize && path.count > bestPath.count) {
                bestSize = cumulativeSize
                bestPath = path
            }

            for dep in adjacency[node] ?? [] {
                // Only follow non-system nodes to find heaviest embedded chain
                guard sizes[dep.target] != nil, !visited.contains(dep.target) else { continue }

                visited.insert(dep.target)
                let depSize = sizes[dep.target] ?? 0
                dfs(
                    node: dep.target,
                    path: path + [dep.target],
                    cumulativeSize: cumulativeSize + depSize,
                    depth: depth + 1,
                    visited: &visited
                )
                visited.remove(dep.target)
            }
        }

        var visited: Set<String> = [root]
        dfs(node: root, path: [root], cumulativeSize: sizes[root] ?? 0, depth: 0, visited: &visited)

        return (maxDepth, DependencyChain(path: bestPath, totalSize: bestSize))
    }
}
