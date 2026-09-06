# swift-crap

Function-level Swift complexity and CRAP scoring, with a reusable engine and CLI. SwiftSyntax measures authored decisions; LLVM or Xcode supplies per-function line execution.

The metric is `crap-line-v1`: **complexity² × (1 − lineCoverage)³ + complexity**. This is explicitly line-coverage CRAP, not the original basis-path variant. Coverage measures execution, not assertion quality.

## Build

Requires Swift 6.3 and macOS 13+ or Linux. Development verification requires Node.js 22+, matching Swift/LLVM tools, and full Xcode on macOS. Dependencies are pinned.

```sh
./scripts/init.sh
./scripts/verify.sh
swift build -c release
.build/release/swift-crap --help
```

Use the release executable directly or copy it to a directory on your PATH. On Linux, `swiftc`, `llvm-profdata` and `llvm-cov` must be available from compatible toolchains. CI runs the portable gate on Linux and real Xcode coverage tests on macOS.

## Capture before gating

Raw coverage JSON cannot establish source freshness. `capture` snapshots source/configuration/test inputs, runs an explicit build/test command, records fresh coverage artifacts, and derives active callable inventory using the captured compiler configuration. `analyze` verifies that evidence before scoring. It never runs tests itself.

For a Swift package, resolve dependencies first, then use a fresh output directory:

```sh
cd /path/to/package
swift package resolve
capture_run="$(mktemp -d)"
build_path="$(swift build --scratch-path "$capture_run/build" --show-bin-path)"
swift-crap capture --root "$PWD" \
  --output "$capture_run/receipt.json" \
  --coverage "$capture_run/coverage.json" \
  --build-description "$build_path/description.json" \
  -- sh -c 'swift test --enable-code-coverage --scratch-path "$1/build" &&
    cp "$(swift test --scratch-path "$1/build" --show-codecov-path)" "$1/coverage.json"' sh "$capture_run"

swift-crap analyze --package "$PWD" \
  --coverage "$capture_run/coverage.json" --provenance "$capture_run/receipt.json"
```

Outputs must not already exist. Failed tests, changed inputs, missing compiler contexts and changed artifacts fail closed. Resolve dependencies and generate source inputs before capture. See [provenance and trust](docs/provenance.md) for the precise guarantees and custom-build context format.

For exploration only, explicitly opt out:

```sh
swift-crap analyze --file Sources/Feature.swift --coverage coverage.json --trust-coverage unverified
```

That report is labeled `unverified`; it does not claim freshness or active-build inventory.

## Select a scope

All scopes accept `--coverage ARTIFACT --provenance RECEIPT`:

```sh
swift-crap analyze --project /path/to/project --coverage coverage.json --provenance receipt.json
swift-crap analyze --package /path/to/package --coverage coverage.json --provenance receipt.json
swift-crap analyze --package /path/to/package --target MyLibrary --coverage coverage.json --provenance receipt.json
swift-crap analyze --file /path/to/project/Sources/Feature.swift --coverage coverage.json --provenance receipt.json
```

Project mode excludes build, dependency, hidden and test directories, plus SwiftPM manifests. Repeated `--exclude PREFIX` applies root-relative component prefixes. Package/target modes use SwiftPM membership, including custom paths and exclusions. Explicit file selection can include tests. Captured analyses retain the receipt's root for identities across narrower scopes.

Xcode target membership comes from Xcode's resolved indexing build graph, including synchronized folders and membership exceptions:

```sh
swift-crap analyze --xcode-project /path/App.xcodeproj --scheme App --target App \
  --configuration Debug --destination 'platform=macOS' \
  --coverage Tests.xcresult --provenance receipt.json
```

See the [Xcode capture example](docs/provenance.md#xcode). The supplied capture command and metadata configuration must match. The analyzer reads real result bundles with `xccov`.

Other build systems can supply `--sources-manifest sources.json --target App`. The JSON shape is `{"root":".","targets":{"App":["Sources/App.swift","Shared"]}}`; root is relative to the manifest, entries relative to root. Exact compiler contexts still come from capture; directory membership is not a substitute for build configuration.

## Reports and gates

Use `--format json` for deterministic machine-readable output, `--threshold 30` to select an absolute gate, and `--baseline previous.json` for a strict no-regression ratchet.

| Exit | Meaning |
| --- | --- |
| 0 | Valid analysis; gate passes |
| 1 | Invalid options, source, provenance, coverage or reconciliation |
| 2 | Valid analysis; gate fails |

Without a baseline, scores strictly above the threshold fail. With a baseline, any increase for an existing ID fails; new functions must satisfy the threshold. Keep selection, compiler/platform, configuration and missing-data policy consistent across comparisons.

Captured analysis requires a baseline labeled `captured` with the same `buildIdentity`. That identity binds the canonical project root, exact selection and exclusions, and compiler contexts. Source inventories and output artifacts are excluded so changed or newly added functions can be compared. A legacy report without an identity cannot silently authorize a trusted gate.

Identity is deliberately conservative and machine-local: changed SDK, compiler or search paths can invalidate a baseline. For repeated local or CI captures, use a stable checkout/build-cache location and fresh receipt/coverage output paths. The baseline is read once; the bytes checked for trust are the bytes used for comparison.

Missing coverage is an error. `--missing zero` explicitly labels absent observations `assumedZero`; it never claims instrumentation. Actual zero execution is `measured`. Generic or compiler-unemitted functions can lack records even after a complete test run. Package-wide tests may also leave executable/example targets uninstrumented.

Repeated LLVM artifacts union execution only when owned executable-line universes match. Nonidentical aggregate-only xccov observations cannot establish a union and are rejected.

JSON includes `schemaVersion`, `metric`, `verification`, optional `buildIdentity`, `functions` and `summary`. Each function contains identity, location, complexity, counts, fraction, CRAP and coverage status. Ordering is stable; reports omit timestamps. The library leaves verification and build identity absent unless its caller supplies them.

## Engine libraries

`CrapCore` exposes models and `AnalysisEngine`; `CrapSyntax` exposes `SwiftSourceAnalyzer`; `CrapCoverage` exposes `CompilerCoverageDecoder`. The core consumes values without launching a build, running tests or importing SwiftSyntax.

`SwiftSourceAnalyzer(configuration:)` uses SwiftIfConfig to traverse active syntax without moving original source positions. Its argument implements the upstream build-configuration capability. The parameterless initializer is an all-branches source inventory, not evidence about a specific build.

See [metric semantics](docs/metrics.md), [architecture](docs/architecture.md), [compatibility evidence](docs/compatibility.md), and [contribution guidance](CONTRIBUTING.md).

## Boundaries

- Only authored callables are inventoried; macro-generated declarations and compiler-generated thunks are not assigned invented source complexity.
- Receipts detect accidental changes, not malicious builds or forged attestations. Captured roots and compiler contexts contain machine-local paths.
- Unsupported or ambiguous syntax, contexts and coverage mappings fail explicitly. Support is established by the published compatibility evidence, not a universal guarantee.
- LLVM expansion is limited to 1,000,000 source lines per function.
- Named identities omit line numbers. Anonymous closures use lexical ordinals; inserting an earlier closure can shift later identities.
- Review [SECURITY.md](SECURITY.md) before running third-party manifests or capture commands.

## License

Apache-2.0; see [LICENSE](LICENSE), [NOTICE](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md). This license is prepared for owner review before the repository is made public.
