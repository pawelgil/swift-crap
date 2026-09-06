# Provenance and build configuration

## Guarantees

Capture requires new output paths, snapshots the project before the supplied command, requires successful completion, derives compiler-aware callable inventory, fingerprints coverage and checks the input snapshot again before writing a receipt. Analysis checks project inventory/content and selected artifacts before and after scoring. A source edit of identical length still invalidates the receipt. Modification times are not evidence.

SHA-256 fingerprints cover regular source-tree inputs, including test sources and build configuration. `.git`, `.build`, `DerivedData`, `.swift-crap` and explicitly declared output artifacts are excluded. Keep build products outside the source tree or in those build directories. Input symlinks may not escape the root. Resolve dependencies and generate source inputs before capture; a capture that changes tracked source/configuration inputs fails.

A receipt is a local, unsigned record, not a security attestation. The command, toolchain and environment are trusted. It cannot prove that an arbitrary command really executed tests or that external dependencies were honest. It does not make unrelated existing coverage fresh. Keep source, receipt and artifacts together and protect them as CI artifacts. Do not pass secrets as command arguments: the receipt records them verbatim.

## Compiler contexts

SwiftPM contexts come from its actual `description.json` Swift compiler commands, including module name, target sources, defines, language mode, SDK and import paths. Module name is semantic: `canImport(CurrentModule)` can depend on it. Xcode contexts come from the resolved indexing graph under the same command's project, scheme, configuration and destination. The compiler is selected from that target's resolved `SWIFT_EXEC` or `TOOLCHAIN_DIR`, preserving explicit overrides; supplemental toolchains such as Metal are not mistaken for competing Swift compilers. Captured products remain available while compiler conditional queries run.

SwiftIfConfig evaluates the parsed conditional structure. A compiler-backed configuration answers conditions such as `os`, `arch`, `canImport`, `swift`, `compiler`, `hasFeature` and custom defines using that context. Parser experimental features are enabled only when confirmed by the compiler. Invalid active syntax is rejected; syntax in regions the compiler deliberately leaves unparsed is not treated as active source. Complexity and callable discovery share the same active regions.

Other build systems can use `--build-context FILE`, a JSON array:

```json
[
  {
    "compiler": "/absolute/path/to/swiftc",
    "arguments": ["-sdk", "/absolute/SDK", "-target", "arm64-apple-macosx13.0", "-DDEBUG", "-swift-version", "6"],
    "directory": "/absolute/project",
    "sources": ["/absolute/project/Sources/Feature.swift"],
    "moduleName": "App"
  }
]
```

The explicit context is the caller's assertion about the invoked build; do not fabricate it from the host platform. Include SDK/import/search paths and compiler flags actually used. When SwiftPM compiles one file in multiple contexts, each is analyzed independently. They are accepted only if the complete active callable inventories agree, including identities, positions and complexity; no search paths are discarded to force a match. Differing inventories fail as ambiguous. Xcode capture requires one architecture. Source membership not represented by a captured compiler context is an error.

## Xcode

Run from the project root with a fresh output directory. Substitute the actual scheme, target and destination; macOS keeps the example independent of simulators.

```sh
capture_run="$(mktemp -d)"
swift-crap capture --root "$PWD" --output "$capture_run/receipt.json" \
  --coverage "$capture_run/Tests.xcresult" \
  --xcode-project "$PWD/App.xcodeproj" --scheme App --target App \
  --configuration Debug --destination 'platform=macOS' \
  -- xcrun xcodebuild -project "$PWD/App.xcodeproj" -scheme App \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$capture_run/DerivedData" \
  -resultBundlePath "$capture_run/Tests.xcresult" -enableCodeCoverage YES test

swift-crap analyze --xcode-project "$PWD/App.xcodeproj" --scheme App --target App \
  --coverage "$capture_run/Tests.xcresult" --provenance "$capture_run/receipt.json"
```

Target selection uses Xcode's resolved sources, not an inferred directory layout. Real XCTest/xcresult coverage and synchronized-folder exceptions are exercised by the macOS integration and executable tests. Workspaces and unusual build frontends can use explicit manifests/contexts; unsupported metadata fails instead of guessing.

## Legacy inputs

`--trust-coverage unverified` opts out of provenance. It uses source inventory across all conditional branches and labels reports `unverified`. This is useful for investigation, not a substitute for captured evidence. `--missing zero` is a separate choice: even captured sources can lack compiler coverage records. An assumed zero remains visible in each function and summary.

Receipts are specific to their source snapshot and local paths. A source change requires a new capture. Baselines intentionally refer to older reports. Captured comparisons require a captured baseline and an identical build identity, which binds the canonical root, exact selection/exclusions and sorted compiler contexts while excluding source inventories and output artifacts. The validated baseline bytes are reused without a second read.

Compiler, SDK and search paths remain in the identity, so it is conservative and machine-local. Use stable checkout/build-cache paths with fresh output artifact paths for repeated captures, and keep missing-data policy consistent. The tool does not infer a portable CI artifact relocation map from suffixes.
