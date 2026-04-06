//
//  swift-tools-version: 6.0
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import PackageDescription

let package = Package(
    name: "BundleProfiler",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "bundle-profiler", targets: ["BundleProfiler"]),
        .library(name: "BundleProfilerKit", targets: ["BundleProfilerKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "BundleProfiler",
            dependencies: [
                "BundleProfilerKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "BundleProfilerKit"
        ),
        .testTarget(
            name: "BundleProfilerKitTests",
            dependencies: ["BundleProfilerKit"]
        ),
    ]
)
