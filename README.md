# BundleProfiler

A command-line tool for analyzing iOS and macOS app bundle sizes. Get a complete breakdown — from high-level category summaries down to individual Mach-O segments, linked dylibs, and per-architecture thinning estimates — for any `.app` or `.ipa`.

## Features

- **File-level breakdown** — classifies every file by type (executable, framework, asset catalog, font, image, etc.) with size and percentage
- **Mach-O section analysis** — native parsing of fat binaries and 64-bit headers with per-segment/section detail (`__TEXT`, `__DATA`, `__LINKEDIT`)
- **Linked dylib inventory** — lists every `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, `LC_REEXPORT_DYLIB`, and `LC_LAZY_LOAD_DYLIB` with version info
- **App thinning estimates** — simulates per-architecture download sizes so you know what users actually download
- **Per-framework breakdown** — total size, binary size, resource size, and code signature size for each embedded framework
- **Duplicate resource detection** — SHA-256 content hashing to find identical files wasting space
- **Asset catalog analysis** — asset counts and sizes from compiled `.car` files via `assetutil`
- **Comparison mode** — diff two bundles to see added/removed/changed files and per-category deltas
- **Size budget enforcement** — CI gate via `check` subcommand: exits non-zero when the bundle exceeds a budget
- **Multiple output formats** — human-readable tree, JSON, Markdown (for PR comments), or self-contained HTML treemap

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

# Markdown output (for PR comments, wikis, etc.)
bundle-profiler analyze MyApp.app --format markdown

# Interactive HTML treemap
bundle-profiler analyze MyApp.app --format html > report.html
open report.html

# Show top 30 largest files (default: 20)
bundle-profiler analyze MyApp.app --top 30

# Skip expensive operations for faster results
bundle-profiler analyze MyApp.app --no-mach-o --no-duplicates
```

### Compare two bundles

```bash
bundle-profiler compare Old.app New.app
bundle-profiler compare Old.ipa New.ipa --threshold 1024
bundle-profiler compare Old.app New.app --format markdown
```

### Check against a size budget (CI)

```bash
# Exits 0 if within budget, 1 if over
bundle-profiler check MyApp.app --budget 50MB

# Markdown output for GitHub PR comments
bundle-profiler check MyApp.app --budget 200MB --format markdown

# Budget accepts human-readable sizes
bundle-profiler check MyApp.app --budget 1.5GB
bundle-profiler check MyApp.app --budget 500KB
```

Example CI step (GitHub Actions):

```yaml
- name: Check bundle size
  run: bundle-profiler check MyApp.app --budget 50MB --format markdown >> "$GITHUB_STEP_SUMMARY"
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

  Linked Libraries (12):
    libSystem.B.dylib  (compat: 1.0.0, current: 1336.0.0)
    libobjc.A.dylib  (compat: 1.0.0, current: 850.0.0)
    ...

APP THINNING ESTIMATES
--------------------------------------------------------------------------------
  Architecture   Estimated    Binary       Resources
  arm64              34.1 MB      15.5 MB  18.6 MB
  x86_64             35.8 MB      17.2 MB  18.6 MB

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
│   ├── Models/         # BundleInfo, FileEntry, FileCategory, MachOInfo, DylibDependency, ThinningEstimate, BudgetResult
│   ├── Analysis/       # BundleAnalyzer, FileWalker, MachOParser, ThinningSimulator
│   ├── Formatting/     # TreeFormatter, JSONFormatter, MarkdownFormatter, HTMLFormatter, SizeFormatter
│   └── Utilities/      # IPAExtractor, BudgetParser
└── BundleProfiler/     # CLI commands (analyze, compare, check)
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

// Linked dylibs
for slice in info.mainExecutable?.slices ?? [] {
    for dep in slice.dependencies {
        print("  \(dep.name) [\(dep.type)] v\(dep.currentVersion)")
    }
}

// App thinning estimates
let thinning = ThinningSimulator().simulate(bundle: info)
for estimate in thinning.estimates {
    print("  \(estimate.architecture): \(SizeFormatter.format(estimate.estimatedSize))")
}

// Budget check
let budget = BudgetResult(
    bundleName: info.bundleName,
    totalSize: info.totalSize,
    budget: 50 * 1_048_576, // 50 MB
    categoryBreakdown: info.categoryBreakdown
)
print("Over budget: \(budget.isOverBudget)")
```

## License

MIT — see [LICENSE](LICENSE).
