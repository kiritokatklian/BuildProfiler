//
//  PathUtilities.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

func resolvePath(_ path: String) -> String {
    if path.hasPrefix("/") || path.hasPrefix("~") {
        return (path as NSString).expandingTildeInPath
    }
    return FileManager.default.currentDirectoryPath + "/" + path
}

func writeOutput(_ content: String, to path: String?) throws {
    if let path {
        try content.write(to: URL(fileURLWithPath: resolvePath(path)), atomically: true, encoding: .utf8)
    } else {
        print(content)
    }
}
