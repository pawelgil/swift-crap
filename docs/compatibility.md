# Open-source Swift compatibility audit

This audit exercises `swift-crap` against released source from three unrelated Apple Swift packages. It is deliberately separate from the repository's fixtures: source was read and complexity decisions were counted before tool output was inspected, while line execution came from per-function `xcrun llvm-cov report --show-functions` records, not from `swift-crap`'s coverage decoder or file-global lines clipped to a source span.

The results below are a macOS snapshot from 2026-09-06. They establish compatibility with the pinned commits and toolchain only; they are not a universal claim about every Swift package or compiler version.

## Pinned corpus

| Package | Upstream release | Exact commit | License | Audited target |
| --- | --- | --- | --- | --- |
| [swift-algorithms 1.2.1](https://github.com/apple/swift-algorithms/releases/tag/1.2.1) | `1.2.1` | `87e50f483c54e6efd60e885f7f5aa946cee68023` | Apache-2.0 with Swift runtime exception | `Algorithms` |
| [swift-collections 1.6.0](https://github.com/apple/swift-collections/releases/tag/1.6.0) | `1.6.0` | `a0cb0954ecb21e4e31b0070e6ed5674e8556685a` | Apache-2.0 with Swift runtime exception | `HeapModule` |
| [swift-argument-parser 1.8.2](https://github.com/apple/swift-argument-parser/releases/tag/1.8.2) | `1.8.2` | `6a52f3251125d74daf04fcbd5e6f08a75d074382` | Apache-2.0 with Swift runtime exception | `ArgumentParser` |

The full machine-readable pins are in `Tests/Compatibility/corpus.json`. Swift Algorithms' unconstrained resolved dependency was explicitly pinned to Swift Numerics `1.1.1`, commit `0c0290ff6b24942dadb83a929ffaaa1481df04a2`.

Each repository was cloned from its official GitHub remote into a fresh directory under `/private/tmp`, checked out detached, and verified with `git rev-parse HEAD`. No upstream remote or tracked source was modified.

## Environment and native test evidence

The runs used:

```text
swift-driver version: 1.148.6
Apple Swift version 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102)
Target: arm64-apple-macosx26.0
Apple LLVM version 21.0.0 Optimized build
```

For each checkout, the native workflow was:

```sh
swift test --enable-code-coverage
xcrun llvm-cov export TEST_BINARY -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata > COVERAGE_JSON
xcrun llvm-cov report TEST_BINARY -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata -ignore-filename-regex='(/Tests/|/.build/|/Benchmarks/)'
xcrun llvm-cov report TEST_BINARY -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata --show-functions SAMPLE_SOURCE...
xcrun llvm-cov show TEST_BINARY -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata SAMPLE_SOURCE...
```

The strict workflow wrapped the build and test run itself, rather than reusing a stale prebuilt test binary:

```sh
swift-crap capture \
  --root CHECKOUT \
  --output RECEIPT \
  --coverage COVERAGE_JSON \
  --build-description CHECKOUT/.build/arm64-apple-macosx/debug/description.json \
  -- zsh scripts/corpus-capture-coverage.sh CHECKOUT COVERAGE_JSON TEST_PRODUCT TEST_LOG
```

Argument Parser added `--coverage CHECKOUT/default.profraw` because its instrumented child process creates that second artifact.

| Package | Native tests | Production region coverage | Function coverage | Line coverage |
| --- | ---: | ---: | ---: | ---: |
| Swift Algorithms | 212 passed, 0 failed | 1,596 / 1,751, 91.15% | 658 / 747, 88.09% | 4,030 / 4,236, 95.14% |
| Swift Collections | 832 XCTest and 13 Swift Testing passed, 0 failed | 9,860 / 12,722, 77.50% | 4,785 / 6,386, 74.93% | 28,371 / 34,637, 81.91% |
| Swift Argument Parser | 564 passed, 0 failed | 2,317 / 2,901, 79.87% | 984 / 1,179, 83.46% | 8,586 / 9,847, 87.19% |

These totals are native `llvm-cov report` totals after excluding test, build, and benchmark paths. They are context only: callable scores below use LLVM's per-function line ownership, including distinct records for nested closures, as required by `crap-line-v1`.

## Independent callable sample

For every row, `C` was counted from source using the metric decision ledger. `LLVM lines` was then taken from that callable's native function record; closures have distinct records, so their lines cannot inflate the enclosing callable. The expected score was calculated as `C × C × (1 - L)³ + C`, with `L = covered / executable`. Finally, the analyzer result was compared with those independent values.

### Swift Algorithms

| Source callable | Manual decision ledger | C | LLVM lines | Hand score | Analyzer | Status |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `Grouped.swift:21`, `Sequence.grouped` | baseline | 1 | 3 / 3 | 1 | C 1, 3 / 3, 1 | match |
| `FirstNonNil.swift:33`, `Sequence.firstNonNil` | baseline + `for` + `if let` | 3 | 8 / 8 | 3 | C 3, 8 / 8, 3 | match |
| `MinMax.swift:14`, `Sequence._minImplementation` | baseline + first `while` + comma condition + second `while` + `guard` | 5 | 21 / 21 | 5 | C 5, 21 / 21, 5 | match |
| `MinMax.swift:33`, explicit partition closure | baseline; nested callable decisions excluded from parent | 1 | 1 / 1 | 1 | C 1, 1 / 1, 1 | match |
| `Partition.swift:238`, `Sequence.partitioned` | baseline + `for` + `if` | 3 | 0 / 14 | 12 | C 3, 0 / 14, 12 | match |

The uncovered partition overload demonstrates the exact zero-coverage calculation: `3² × (1 - 0)³ + 3 = 12`.

### Swift Collections

| Source callable | Manual decision ledger | C | LLVM lines | Hand score | Analyzer | Status |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `Heap.swift:68`, `Heap.init()` | baseline | 1 | 3 / 3 | 1 | C 1, 3 / 3, 1 | match |
| `Heap.swift:205`, `Heap.popMax` | baseline + `guard`; closure decisions excluded | 2 | 20 / 20 | 2 | C 2, 20 / 20, 2 | match |
| `Heap.swift:211`, explicit update closure | baseline + two `if` statements | 3 | 11 / 11 | 3 | C 3, 11 / 11, 3 | match |
| `Heap+UnsafeHandle.swift:102`, `bubbleUp` | baseline + `guard` + compound `if` (`if`, two `&&`, one `||`) + `if` + two `while` statements with comma conditions | 11 | 26 / 26 | 11 | C 11, 26 / 26, 11 | match |
| `Heap+UnsafeHandle.swift:215`, `_minDescendant` | baseline + four `if` statements | 5 | 31 / 31 | 5 | C 5, 31 / 31, 5 | match |

### Swift Argument Parser

| Source callable | Manual decision ledger | C | LLVM lines | Hand score | Analyzer | Status |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `StringExtensions.swift:145`, `editDistance(to:)` | baseline + 2 initial conditions + prefix loop and 2 `&&` + suffix loop and `&&` + three guards, including one `&&` + two `for` loops + inner `if` | 16 | 92 / 92 | 16 | C 16, 92 / 92, 16 | match |
| `SplitArguments.swift:629`, `parseIndividualArg` | baseline + `if let` + three outer switch clauses + two inner switch clauses + `for` + two final switch clauses | 10 | 46 / 52 | 10.153618570778335 | C 10, 46 / 52, 10.153618570778335 | match |
| `SplitArguments.swift:633`, explicit `firstIndex` closure | baseline | 1 | 1 / 1 | 1 | C 1, 1 / 1, 1 | match |
| `NameSpecification.swift:252`, `Element.name(for:)` | baseline + five non-default switch clauses + `guard` + ternary | 8 | 16 / 22 | 9.298271975957926 | C 8, 16 / 22, 9.298271975957926 | match |
| `Mutex.swift:46`, `_Lock.initialize` on macOS | baseline; only the `canImport(os)` region is active | 1 | 3 / 3 | 1 | C 1, 3 / 3, 1 | match |

The two partial-coverage calculations are `10² × (6 / 52)³ + 10 = 10.153618570778335` and `8² × (6 / 22)³ + 8 = 9.298271975957926`. An exploratory mutex result was C 3 because inactive `#elseif` clauses were counted without compiler configuration. The captured compiler-context result above is the acceptance result: C 1 and an exact native-score match.

## Full-scope and target attempts

Before captured compiler context was available, explicit unverified runs found the following gaps. These are retained because failed real-project attempts are part of the compatibility evidence:

| Package and scope | Default `--missing error` result | Explicit `--missing zero` result |
| --- | --- | --- |
| Algorithms target | failed on inactive `#if ALGORITHMS_DARWIN_ONLY` callable | 537 total, 534 measured, 3 assumed |
| Collections `HeapModule` target | failed on inactive `#if COLLECTIONS_INTERNAL_CHECKS` callable | 82 total, 80 measured, 2 assumed |
| Collections package | failed to parse `UniqueBox.swift`'s feature-gated `mutate` accessor | not treated as a successful package score |
| Argument Parser target | failed on synthesized/default `Argument.init()` with no native record | 915 total, 910 measured, 5 assumed |
| Argument Parser package | failed on unlinked `Examples/color/Color.run()` | 1,163 total, 943 measured, 220 assumed |

Those runs were exploratory and are not release gates. In particular, `--missing zero` is explicit debt accounting, not proof that coverage exists.

Strict capture snapshots source/configuration/test inputs, binds the new coverage artifact by digest, and records the compiler arguments for each source. The final captured attempts are:

| Package and scope | Result | Verification |
| --- | --- | --- |
| Algorithms `Algorithms` target | 534 measured, 0 assumed | captured receipt |
| Algorithms package | 534 measured, 0 assumed | captured receipt |
| Collections `HeapModule` target | 80 measured, 0 assumed | captured receipt |
| Collections package | default policy failed on `_HTable.deinit`; explicit zero reported 5,003 total, 4,992 measured, 11 assumed | captured receipt |
| Argument Parser `ArgumentParser` target | default policy failed on declaration-only `Argument.init()`; explicit zero reported 914 total, 910 measured, 4 assumed | captured receipt |
| Argument Parser package | default policy failed on unlinked `Examples/color/Color.run()`; explicit zero reported 1,162 total, 943 measured, 219 assumed | captured receipt |

The first strict Collections capture also found an analyzer defect: its compiler probe emitted `_objectFormat(Wasm)`, while the compiler condition is spelled `objectFormat(Wasm)`. After that spelling was corrected and covered, capture succeeded. The first strict Argument Parser attempt found a tracked directory symlink that the input snapshot initially could not fingerprint; the retry passed that stage after logical-path, resolved-directory traversal was added. It then exposed semantically equivalent normal and `-tool` SwiftPM contexts for the same source, which the initial raw-context equality check rejected as ambiguous. The final implementation analyzes each claiming context and accepts a multiply owned source only when its normalized callable inventories are identical. Each failed attempt and its stderr remains in the raw workspace.

A parser recovery-boundary fix changed the Collections package inventory from the pre-release 5,000 / 4,986 / 14 result to the final 5,003 / 4,992 / 11 result above. Three ordinary `_read { ... }` calls that had been mistaken for accessors became their three enclosing getters and three nested closures. A separate native report confirms the real LLVM records: `BitSet.count` is 3 / 3 and its closure is 1 / 1, `BitSet.startIndex` is 3 / 3 and its closure is 1 / 1, and the range-members subscript is 26 / 26 with its `_read` closure at 23 / 23. This is a corrected syntax inventory, not assumed coverage.

Argument Parser's package tests do not link every example and tool product selected by package scope. A default full-package failure for those sources is therefore correct; a target-scoped score is the meaningful gate. A source callable such as a declaration-only default initializer can also lack a matching LLVM function record even when nearby code executes. Such records must remain errors unless the caller deliberately selects `--missing zero`.

Argument Parser's coverage run also creates a root-level `default.profraw` through an instrumented child process. The final capture declared that raw profile as a second fresh coverage output, so it was excluded from the before/after input comparison and bound into the receipt. Analysis selected only the captured LLVM JSON; the raw intermediate was preserved without asking the JSON decoder to read it.

## Raw evidence and reproduction

The audit workspace was `/private/tmp/swift-crap-oss.mnAcPV`. Important raw files from the initial native run are:

| Artifact | SHA-256 |
| --- | --- |
| `swift-algorithms.coverage.json` | `40415b3f5b7b1cb7903e911c5d69db93ee11d167d051b105c8feebae1a4f8174` |
| `swift-collections.coverage.json` | `0191a00026f4c1993b37c40760dd536ad505f2828eab4fcb1f6c190898b7c1d8` |
| `swift-argument-parser.coverage.json` | `e344d178f726a076c6b8175bd438e205e941fef84de741cc7def2403e43d1b5a` |
| `swift-algorithms.strict.native-show.txt` | `2d1d5fb309adeec05b0daef267eaecc3589bed22d356682f07590c61a1efbfa5` |
| `swift-algorithms.native-functions.txt` | `aad22df0c37246f3869bf07177bbb577652b7c04d5a9b711aa6e521998bd2570` |
| `swift-collections.native-show.txt` | `ce567b70cf645e10d21ee704ceeceaff54db99110cf5de6d5fc1da405e080939` |
| `swift-collections.native-functions.txt` | `7803d724c29ef730cdc08584f6f9a3e50a618a4270011340e7f0f63d210fe666` |
| `swift-argument-parser.native-show.txt` | `fdf0c56a76e5ebf8682e31c167df5e438e842f177f915253b08c3ddcebbc6a30` |
| `swift-argument-parser.native-functions.txt` | `b1760c4adae52bfa5411a84485e992b971a6f96b2bd6cd866cdc1e04626e4b14` |
| `swift-algorithms.strict-v6.coverage.json` | `e57170e7f08b1b3515f9c52d4ae346e3c27ab6f4c92f74262ac907df5850c64d` |
| `swift-algorithms.strict-v6.receipt.json` | `46dcf9ce41d49c2c84075fc9e56eb70bde5aa548a3edc2039eecb5b5957fe1f5` |
| `swift-algorithms.strict-v6.tests.log` | `4ed9f49130c8954ef2160ed5f8583ec94c2284ad8594109db08468168fcb276a` |
| `swift-collections.strict-v6.coverage.json` | `71d69eb76d8606b60028da546f0c600d79b36a70707417653306f7ce3dfd798c` |
| `swift-collections.strict-v6.receipt.json` | `fca9241623ca38188c08751ef35fd2ebe82883b0af5a43a09058cd383de58929` |
| `swift-collections.strict-v6.tests.log` | `2e8aa285368d2f757820d1995931f9b5b340b1158b4769c7b0a84de0447c2a73` |
| `swift-collections.final-v6.bitset-native-functions.txt` | `8b79e3653052497dfda874ee1688e618984b4d0ab37d8f72fba87a50881ee2b7` |
| `swift-argument-parser.strict-v6.coverage.json` | `31cbe02ab0f8bb5d3cf224659b7c37ef2a9c5ad61a7d55428ec2fa556e7fd801` |
| `swift-argument-parser.strict-v6.receipt.json` | `7a9c7eca99e5f09247252ab6b25b4e1b17c26875b4333f192d78084be444e7a7` |
| `swift-argument-parser.strict-v6.tests.log` | `ae50badecc72077343fda45a1d52aaeb9cec5df3d23d4c7de48ee5077b80da4c` |
| `swift-argument-parser/default.profraw` | `f9f81156d6a08e94850bb4590a166b0e889860df30cf7159bb93b8e476aae962` |

The final twelve target/package and missing-policy attempts used an immutable copy of the module-aware debug CLI at `swift-crap.audit-bin-v6`, SHA-256 `4ea0abab3e0e27c1e6915461fe7a2926fb8749560be669a91a0c375e01a142a5`. The six successful explicit-zero reports carry captured build identities; target identities are `df7b8435456213801ad011cb366d28b7c3c3df74afea589031bfe4a8e402378f`, `c7560fb7ebc7897bfa864f80b8eea3552538faeb78bd1aefdaef68a1b3d2e332`, and `78c38608b56570dc750828d695a60cd39076fde50ecd21129875b0e8de43dcdd` in corpus order.

The workspace also contains the complete native reports, analyzer JSON, standard-error failures, coverage exports, and capture receipts described above. These paths are provenance for this dated run, not committed fixtures.

The first clean harness attempt also remains preserved. It failed before any package build because targeted `swift package resolve swift-numerics --version 1.1.1` cannot name a dependency before SwiftPM has resolved the graph. The harness now performs an initial graph resolution, pins Swift Numerics to the manifest version, and verifies the resolved checkout commit before building.

To recreate the corpus in a new temporary directory and retain equivalent raw artifacts:

```sh
swift build
./scripts/corpus-compatibility.sh .build/debug/swift-crap
```

The script requires macOS, Zsh, Git, `jq`, `shasum`, Swift, Xcode, and `xcrun`. It prints its fresh workspace path. At bootstrap it copies the requested CLI into the artifact directory, records its SHA-256 and the complete Swift/Xcode/LLVM toolchain versions, and uses only that immutable copy for the long run. It reads and verifies every checkout hash from the manifest, locks the only transitive dependency, builds coverage-instrumented tests, executes them within `swift-crap capture`, exports coverage with native LLVM, runs target and package analysis under both missing-coverage policies, and stores exit statuses, stderr, native per-function reports, source listings, receipts, and JSON reports. `scripts/corpus-assertions.sh` then enforces all twelve expected statuses, six scope summaries, three exact missing-coverage errors, and the 15 sampled complexity/line/score tuples; an unexpected failure cannot produce a green corpus run. Network access and several minutes are required; Swift Collections dominates runtime.
