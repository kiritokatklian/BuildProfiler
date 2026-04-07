//
//  OutputFormat.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import ArgumentParser

enum OutputFormat: String, ExpressibleByArgument {
    case tree
    case json
    case html
    case markdown
}
