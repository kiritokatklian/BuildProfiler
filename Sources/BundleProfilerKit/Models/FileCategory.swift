//
//  FileCategory.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//
import Foundation

/// Classification of files within an app bundle.
public enum FileCategory: String, Codable, Sendable, CaseIterable, Comparable {
    case executable
    case framework
    case assetCatalog
    case storyboard
    case xib
    case strings
    case font
    case plist
    case codeSignature
    case image
    case audio
    case video
    case mlModel
    case metalLibrary
    case appExtension
    case localization
    case header
    case moduleMap
    case other

    public var displayName: String {
        switch self {
        case .executable: "Executables"
        case .framework: "Frameworks"
        case .assetCatalog: "Asset Catalogs"
        case .storyboard: "Storyboards"
        case .xib: "XIBs"
        case .strings: "Strings"
        case .font: "Fonts"
        case .plist: "Plists"
        case .codeSignature: "Code Signatures"
        case .image: "Images"
        case .audio: "Audio"
        case .video: "Video"
        case .mlModel: "ML Models"
        case .metalLibrary: "Metal Libraries"
        case .appExtension: "App Extensions"
        case .localization: "Localizations"
        case .header: "Headers"
        case .moduleMap: "Module Maps"
        case .other: "Other"
        }
    }

    public static func classify(path: String) -> FileCategory {
        let ext = (path as NSString).pathExtension.lowercased()
        let filename = (path as NSString).lastPathComponent

        // Code signature directory
        if path.contains("_CodeSignature") || filename == "CodeResources" || filename == "CodeSignature" {
            return .codeSignature
        }

        // Localization bundles
        if path.contains(".lproj/") || ext == "lproj" {
            return .localization
        }

        // Framework bundles
        if path.contains(".framework/") || ext == "framework" {
            return .framework
        }

        // App extensions
        if ext == "appex" || path.contains(".appex/") {
            return .appExtension
        }

        switch ext {
        // Asset catalogs
        case "car":
            return .assetCatalog

        // Interface files
        case "storyboardc", "storyboard":
            return .storyboard

        case "nib", "xib":
            return .xib

        // Strings
        case "strings", "stringsdict":
            return .strings

        // Fonts
        case "ttf", "otf", "ttc", "woff", "woff2":
            return .font

        // Property lists
        case "plist":
            return .plist

        // Images
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif", "tiff", "tif", "bmp", "ico", "pdf":
            return .image

        // Audio
        case "mp3", "wav", "aac", "m4a", "caf", "aiff", "aif", "flac", "ogg":
            return .audio

        // Video
        case "mp4", "mov", "m4v", "avi", "mkv":
            return .video

        // ML Models
        case "mlmodel", "mlmodelc", "mlpackage":
            return .mlModel

        // Metal
        case "metallib":
            return .metalLibrary

        // Headers
        case "h", "hh", "hpp":
            return .header

        // Module maps
        case "modulemap":
            return .moduleMap

        // Executables (no extension in Mach-O binaries — handled by caller)
        case "dylib":
            return .executable

        default:
            return .other
        }
    }

    public static func < (lhs: FileCategory, rhs: FileCategory) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .executable: 0
        case .framework: 1
        case .assetCatalog: 2
        case .image: 3
        case .font: 4
        case .storyboard: 5
        case .xib: 6
        case .strings: 7
        case .localization: 8
        case .plist: 9
        case .mlModel: 10
        case .metalLibrary: 11
        case .audio: 12
        case .video: 13
        case .appExtension: 14
        case .codeSignature: 15
        case .header: 16
        case .moduleMap: 17
        case .other: 18
        }
    }
}
