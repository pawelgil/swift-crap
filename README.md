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

Captured Xcode target membership comes from the selected target's actual compiler invocation, including synchronized folders and membership exceptions:

```sh
swift-crap analyze --xcode-project /path/App.xcodeproj --scheme App --target App \
  --configuration Debug --destination 'platform=macOS' \
  --coverage Tests.xcresult --provenance receipt.json
```

See the [Xcode capture example](docs/provenance.md#xcode). The supplied capture command and metadata configuration must match, and the target must compile during capture. Capture automatically freezes precise LLVM coverage in the receipt, so analysis remains independent of DerivedData after capture. Keep the original result bundle for provenance checks. Legacy receipts still use `xccov` aggregates.

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

The CLI writes a warning to stderr when a report contains assumed-zero scores, for both JSON and text output. Warnings do not change the selected gate policy or exit code. JSON on stdout remains machine-readable; retain stderr alongside saved reports. Machine consumers can identify affected functions through `coverageStatus: "assumedZero"` and `summary.assumedFunctions`.

Repeated LLVM artifacts union execution only when owned executable-line universes match. Nonidentical aggregate-only xccov observations cannot establish a union and are rejected.

JSON includes `schemaVersion`, `metric`, `verification`, optional `buildIdentity`, `functions` and `summary`. Each function contains identity, location, complexity, counts, fraction, CRAP and coverage status. Ordering is stable; reports omit timestamps. The library leaves verification and build identity absent unless its caller supplies them.

## Missing compiler coverage

Some code can run during tests without the Swift compiler producing a coverage record that belongs to that authored function. For example, an `@Observable` property's `didSet` can execute and change state while its own coverage record is absent. This is different from a recorded function that ran zero times: the former is unknown; the latter has measured zero coverage.

Our native fixtures also demonstrate gaps for authored closures inside `#Preview` and unavailable initializers. These examples are not an exhaustive list, and not every observer or macro use is affected. Macros can move or replace authored code, including in custom macros; a missing record alone does not establish the cause. Swift tracks missing instrumentation for attached macros in [issue #91304](https://github.com/swiftlang/swift/issues/91304); a [compiler maintainer confirms the limitation](https://github.com/swiftlang/swift/issues/91304#issuecomment-5209795589).

`swift-crap` scores only the functions and closures you wrote. It does not score hidden macro-generated machinery, borrow a neighboring function's coverage, or reconstruct missing execution from a passing test. It cannot promise a fully measured CRAP report when the compiler omits records. No patched compiler is required or bundled.

### What you can do

1. Check that coverage was enabled, the selected target was built and included in the coverage artifacts, and the inputs match the source. Recapture after changes. Missing coverage can be a build/input problem, not just a compiler limitation.
2. Where it makes the code clearer, move substantial observer or macro-argument logic into an ordinary authored helper. Keep the helper outside the code being replaced by a macro. For example:

   ```swift
   import Observation

   @Observable
   final class Counter {
       var value = 0 {
           didSet { valueDidChange(from: oldValue) }
       }
       private(set) var changeCount = 0

       private func valueDidChange(from oldValue: Int) {
           guard value != oldValue else { return }
           changeCount += 1
       }
   }
   ```

   Test this by assigning `value` and checking `changeCount`, including unchanged and changed values. That exercises the observer-to-helper connection, not just the helper in isolation. Ordinary helpers can receive their own measured coverage and CRAP scores. The small `didSet` body may still have no record: this reduces the unmeasured logic; it does **not** repair the compiler gap or make a strict whole-project analysis pass. A helper transformed by another macro may encounter the same limitation.
3. Keep the default `--missing error` for gates that require complete measured evidence. For exploration, `--missing zero` produces a report with explicit assumptions and a warning; it does not recover coverage. A passing gate under that policy can still contain unknown coverage. An intentionally narrower file/target scope can help inspect measurable code, but is not a full-project result.

Do not remove useful tests, change behavior, or exclude difficult code just to make a score look complete. If a function is deliberately unavailable, accepting that its coverage is missing may be the appropriate outcome.

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
