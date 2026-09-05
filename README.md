# swift-crap

A reusable Swift engine and command-line tool for function-level CRAP scores. SwiftSyntax measures callable complexity; LLVM or Xcode coverage supplies measured execution. The CLI supports a source project, a Swift package, a target, or one Swift file.

The metric is `crap-line-v1`: `complexity² × (1 − lineCoverage)³ + complexity`. Coverage measures execution, not assertion quality. The original CRAP proposal used basis-path coverage; this tool explicitly uses function-level line coverage because that is available from the Swift toolchain.

## Build and verify

Requires Swift 6.3 and macOS 13+ or Linux. Dependencies are pinned in `Package.resolved`. Development verification also requires Node.js 22+ and the LLVM coverage tools from the same toolchain used by `swiftc`.

```sh
./scripts/init.sh
./scripts/verify.sh
swift build -c release
.build/release/swift-crap --help
```

On macOS the integration tests use `xcrun`. On Linux, `swiftc`, `llvm-profdata`, and `llvm-cov` must be available on `PATH` and belong to compatible toolchains.

## Generate coverage

Run the project's tests successfully with instrumentation before analyzing it:

```sh
swift test --package-path /path/to/package --enable-code-coverage
swift test --package-path /path/to/package --show-codecov-path
```

Use the JSON path printed by SwiftPM. For Xcode, enable code coverage in the test run and export the result:

```sh
xcrun xccov view --report --json /path/to/Tests.xcresult > coverage.json
```

The scorer reads artifacts and never executes the analyzed project's tests. Package scope evaluates its SwiftPM manifest to obtain target membership, using isolated temporary build/cache paths and disabling automatic dependency resolution. Run only manifests you trust, just as with SwiftPM itself.

## Select a scope

```sh
swift-crap analyze --project /path/to/project --coverage coverage.json
swift-crap analyze --package /path/to/package --coverage coverage.json
swift-crap analyze --package /path/to/package --target MyLibrary --coverage coverage.json
swift-crap analyze --file /path/to/project/Sources/Feature.swift --root /path/to/project --coverage coverage.json
```

Project scope recursively discovers Swift sources, excluding build, dependency, hidden, and test directories. Use repeated `--exclude` root-relative path prefixes for additional exclusions. Package and target scopes use SwiftPM's declared source membership, including custom paths and source exclusions. Explicit file selection also works for test files. `--root` stabilizes relative identities when comparing narrower scopes with a project report.

For Xcode and other build systems, provide target membership explicitly:

```json
{
  "root": ".",
  "targets": {
    "MyApp": ["App/Sources", "Shared/Feature.swift"]
  }
}
```

```sh
swift-crap analyze --sources-manifest sources.json --target MyApp --coverage coverage.json
```

The manifest root is relative to the manifest file. Target entries are relative to that root and may be files or directories. This version does not infer Xcode target membership from `.pbxproj` files.

## Reports and gates

```sh
swift-crap analyze --project . --coverage unit.json --coverage integration.json --format json --threshold 30
swift-crap analyze --project . --coverage current.json --baseline baseline.json --format json
```

Repeated LLVM observations union executed lines when their function mappings agree. Aggregate-only xccov reports cannot establish a union when observations differ; the tool rejects that ambiguity. Generate a combined Xcode coverage result before importing it.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Valid analysis; gate passes |
| 1 | Invalid options, source, coverage, identity, or reconciliation |
| 2 | Valid analysis; gate fails |

Without a baseline, scores strictly above the threshold fail. With a baseline, existing functions may retain their score, but any increase fails; new functions must satisfy the threshold. A baseline must use the same schema and metric, with unique callable IDs. Keep the same root, source selection, compiler, platform, and coverage policy across comparisons.

Missing required coverage is an error by default. `--missing zero` explicitly scores absent observations as zero coverage and labels each one `assumedZero`; it does not claim those functions were instrumented. A recorded function with zero execution remains `measured`.

JSON reports contain `schemaVersion`, `metric`, `functions`, and `summary`. Functions include their qualified identity, location, complexity, measured counts, coverage fraction, CRAP score, and coverage status. Ordering and JSON keys are deterministic. Text is available with `--format text`.

## Engine libraries

`CrapCore` exposes the callable/coverage model and `AnalysisEngine`. `CrapSyntax` exposes `SwiftSourceAnalyzer`, and `CrapCoverage` exposes `CompilerCoverageDecoder`. The core engine accepts values without reading source contents, launching subprocesses, or importing SwiftSyntax. Path reconciliation resolves filesystem symlinks; callers must supply a consistent analysis root.

```swift
import CrapCore
import CrapCoverage
import CrapSyntax

let callables = try SwiftSourceAnalyzer().analyze(source: source, file: "Sources/Feature.swift")
let coverage = try CompilerCoverageDecoder().decode(coverageJSON)
let report = try AnalysisEngine().analyze(
    callables: callables,
    coverage: coverage.records,
    root: projectRoot,
    missing: .error,
    threshold: 30
)
```

See [metric semantics](docs/metrics.md), [architecture](docs/architecture.md), and the executable tests for the behavioral contract.

## Current boundaries

The source inventory covers authored callables. It does not expand macros or evaluate build-specific conditional compilation. Platform-inactive code and compiler-uninstrumentable source can therefore require explicit scope selection or an acknowledged missing-coverage policy. Missing data never silently becomes a successful measurement.

Coverage exports do not prove which source revision produced them. Supply artifacts from the exact source revision and build configuration being analyzed; source locations alone cannot detect every stale artifact. Ambiguous mappings are rejected.

LLVM coverage expansion is limited to 1,000,000 source lines per function. Larger spans fail explicitly before allocation. This guards against tiny malformed artifacts requesting unbounded memory.

Anonymous closure identities are relative to their enclosing declaration and lexical ordinal. Inserting an earlier anonymous closure changes later ordinals. Named callable IDs include qualified signatures and exclude line numbers.
