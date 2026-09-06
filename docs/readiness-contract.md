# Release readiness contract

The repository remains private until its owner explicitly requests publication.

## Trustworthy gates

`analyze` remains read-only and never runs the analyzed project's tests. A gate requires a capture receipt by default. Legacy coverage imports require the explicit `--trust-coverage unverified` opt-in and are labeled unverified in reports.

`capture --root ROOT --output RECEIPT --coverage ARTIFACT [--build-description FILE | --build-context FILE | --xcode-project PATH --scheme NAME --target NAME] -- COMMAND ARGUMENTS...` is an explicit build/test workflow. It snapshots project inputs before invoking the supplied command, requires new coverage outputs, requires successful command completion and unchanged inputs, and records SHA-256 digests of the inputs and outputs alongside compiler contexts and the command. It cannot attest to a malicious command or compromised compiler. It protects against accidental stale/mismatched inputs, not a hostile author forging a receipt.

An analysis validates the receipt, current project input inventory and contents, and every selected coverage artifact. Source selection may narrow to a package, target or file within the captured root. Sources outside captured compiler contexts fail. Source changes during analysis must fail rather than combine versions. Build products, VCS state and capture outputs are excluded from the input snapshot; source/configuration/test inputs are included. Resolve dependencies and generate source inputs before capture. Changing those inputs during capture is an error.

## Build-aware inventory

Compiler contexts come from a SwiftPM build description, actual Xcode SwiftDriver invocations in the new result bundle, or an explicit context manifest for other build systems. Each context records compiler, working directory, arguments, module and source membership. Compiler-backed conditional queries use that context, including search paths, SDK, target, language mode, custom conditions and feature flags. SwiftIfConfig traverses only active regions in the original source tree, retaining coordinates. A source claimed by multiple contexts is analyzed under each; only identical active inventories can be reconciled. Unknown or ambiguous contexts/conditions fail closed.

Xcode capture binds resolved target membership and actual compiler settings, not directory guesses or handwritten project-file parsing. Standalone unverified selection uses the resolved indexing graph. Capture requires the selected target to compile and automatically freezes precise LLVM coverage alongside its result-bundle binding. Later analysis must not depend on DerivedData. Real XCTest execution exercises native result bundles; portable LLVM support remains tested on macOS and Linux.

## Independent evidence

Pinned upstream Swift projects are built and tested with coverage. Audit records include upstream commit/license, toolchain, exact commands, successful and failed full-scope runs, independently counted decision ledgers, native LLVM line counts and hand-calculated CRAP scores. A match is not established by comparing the analyzer with itself. Failures become regression tests and fixes, not exclusions disguised as support.

## Publication checklist

Unit, compiler integration and executable end-to-end tests are required. The full local gate and hosted platform jobs must pass. Review must cover correctness, testing, architecture, simplification and stale code. License, notices, contribution/security guidance, installation/usage, limitations and reproducible compatibility evidence must be present. No explanatory source comments, hidden assumptions or unsupported universal-readiness claims.
