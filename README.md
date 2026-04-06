# BundleProfiler

A command-line tool for analyzing iOS and macOS app bundle sizes. Get a complete breakdown — from high-level category summaries down to individual Mach-O segments — for any `.app` or `.ipa`.

## Features

- **File-level breakdown** — classifies every file by type (executable, framework, asset catalog, font, image, etc.) with size and percentage
- **Mach-O section analysis** — native parsing of fat binaries and 64-bit headers with per-segment/section detail (`__TEXT`, `__DATA`, `__LINKEDIT`)
- **Per-framework breakdown** — total size, binary size, resource size, and code signature size for each embedded framework
- **Duplicate resource detection** — SHA-256 content hashing to find identical files wasting space
- **Asset catalog analysis** — asset counts and sizes from compiled `.car` files via `assetutil`
- **Comparison mode** — diff two bundles to see added/removed/changed files and per-category deltas
- **Multiple output formats** — human-readable tree with bar charts, or machine-readable JSON

## Installation

### From source

```bash
git clone https://github.com/user/BundleProfiler.git
cd BundleProfiler
swift build -c release
```

The binary will be at `.build/release/bundle-profiler`. Copy it to your PATH:

```bash
cp .build/release/bundle-profiler /usr/local/bin/
```

### Requirements

- macOS 13+
- Swift 6.0+
- Xcode Command Line Tools (for `assetutil` asset catalog analysis)

## Usage

### Analyze a bundle

```bash
# Analyze a .app bundle
bundle-profiler analyze MyApp.app

# Analyze an .ipa file
bundle-profiler analyze MyApp.ipa

# JSON output
bundle-profiler analyze MyApp.app --format json

# Show top 30 largest files (default: 20)
bundle-profiler analyze MyApp.app --top 30

# Skip expensive operations for faster results
bundle-profiler analyze MyApp.app --no-mach-o --no-duplicates
```

### Compare two bundles

```bash
bundle-profiler compare Old.app New.app
bundle-profiler compare Old.ipa New.ipa --threshold 1024 --format json
```

### Run from source without installing

```bash
swift run bundle-profiler analyze /path/to/MyApp.app
```

## Example Output

```
MyApp.app                                              Total: 48.3 MB
================================================================================

CATEGORY BREAKDOWN
--------------------------------------------------------------------------------
  Executables            12.4 MB   25.7%  ████████████▉
  Frameworks             18.6 MB   38.5%  ███████████████████▎
  Asset Catalogs          8.2 MB   17.0%  ████████▌
  Localizations           3.1 MB    6.4%  ███▏
  ...

MACH-O ANALYSIS: MyApp (arm64)
--------------------------------------------------------------------------------
    __TEXT         8.2 MB   66.1%
    __DATA         1.4 MB   11.3%
    __LINKEDIT     2.2 MB   17.7%

EMBEDDED FRAMEWORKS
--------------------------------------------------------------------------------
  Alamofire.framework     5.2 MB    (binary: 4.8 MB, resources: 0.2 MB)
  Kingfisher.framework    4.1 MB    (binary: 3.4 MB, resources: 0.5 MB)

DUPLICATE RESOURCES                                  Wasted: 340 KB
--------------------------------------------------------------------------------
  icon_star.png (12 KB x 3 copies)                   Wasted: 24 KB
```

## Architecture

Two SPM targets:

- **BundleProfilerKit** — library with all analysis logic, zero external dependencies (only Foundation and CryptoKit)
- **BundleProfiler** — thin CLI executable using [swift-argument-parser](https://github.com/apple/swift-argument-parser)

```
Sources/
├── BundleProfilerKit/
│   ├── Models/         # BundleInfo, FileEntry, FileCategory, MachOInfo, etc.
│   ├── Analysis/       # BundleAnalyzer, FileWalker, MachOParser, etc.
│   ├── Formatting/     # TreeFormatter, JSONFormatter, SizeFormatter
│   └── Utilities/      # IPAExtractor
└── BundleProfiler/     # CLI commands (analyze, compare)
```

### Using as a library

Add BundleProfilerKit as a dependency to programmatically analyze bundles:

```swift
import BundleProfilerKit

let analyzer = BundleAnalyzer(options: .init(analyzeMachO: true, detectDuplicates: true))
let info = try analyzer.analyze(path: "/path/to/MyApp.app")

print("Total size: \(SizeFormatter.format(info.totalSize))")
print("Frameworks: \(info.frameworks.count)")
print("Wasted by duplicates: \(SizeFormatter.format(info.totalWastedBytes))")
```

## License

MIT — see [LICENSE](LICENSE).
