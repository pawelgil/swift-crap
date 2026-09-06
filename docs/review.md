# Implementation review

## Intent

Build a standalone source-level Swift CRAP engine and CLI with project, package, target, and file scopes. Establish behavior through public unit tests, real compiler integration, and executable acceptance tests before considering implementation complete.

## Accepted findings

- Separate callable complexity: nested closures, local functions, accessors, and local types must not inflate their enclosing callable's complexity.
- Stable identity: include qualified signatures, generic constraints, static declarations, and conditional-branch context; exclude source positions from named IDs.
- Compiler authority: derive function line execution through LLVM segment semantics and compare with native per-function reports, including short-circuit autoclosures.
- Coverage ownership: prevent same-line siblings, generated closures/default arguments, broad spans, and unrelated file suffixes from donating execution to a source callable.
- Strict input validation: reject inconsistent line universes, nonidentical aggregate observations, invalid parent links, malformed baselines, and excessive coverage expansion.
- Source selection: validate roots before metadata execution, honor declared SwiftPM membership, refuse symlink escapes, and reapply exclusions to canonical paths.
- Diagnostics and portability: preserve artifact paths in errors and use platform-appropriate process exits.
- Architecture: retain a small public engine facade; separate validation, reconciliation, measurement, and baseline policy into cohesive internal types.
- Provenance: reject changed source contents, input membership, artifacts, failed commands and reused output paths; canonicalize path aliases without changing the compiler driver's invoked name.
- Build configuration: use compiler-backed conditional and parser-feature queries, including vendor version components and `objectFormat`, and ignore diagnostics only where the compiler leaves syntax unparsed.
- Callable recovery: recognize addressors and conditional accessors without promoting similarly named helpers nested inside ordinary getter closures.
- Duplicate SwiftPM builds: analyze shared source under every claiming context and reconcile only identical active callable inventories; never discard search paths to manufacture equality.
- Xcode: use resolved target membership, preserve synchronized-folder exceptions, reject multi-architecture ambiguity and bind the exact selector to the captured inventory. Exercise real XCTest result bundles.
- Baseline trust: require captured status and an exact build identity; reuse the same validated bytes during scoring. Do not bind source inventories or output artifacts into identity, since baselines must survive source evolution.
- Repository reality: preserve failed upstream attempts, compare manually counted decisions with native per-function coverage and keep missing compiler records distinct from measured zero execution.
- Hosted portability: replace macOS-only temporary-path assumptions with real portable symlink fixtures, keep the native Xcode fixture compatible with its bundled compiler, and resolve the actual Swift compiler from target build settings rather than rejecting supplemental Metal toolchains.
- Module semantics: retain SwiftPM's module name in compiler arguments; a native counterexample and executable capture test prove that omitting it changes `canImport(CurrentModule)`.
- Architecture selection: an explicit Xcode destination architecture does not narrow a universal `ARCHS` build. A native two-slice framework counterexample requires validating effective build architectures independently of the execution destination.
- Actual Xcode compilation: simulator indexing metadata can describe a device SDK. Capture reads the real result bundle's SwiftDriver command, preserves its SDK/target/flags and rejects incremental results without a selected-target invocation.
- Precise evidence lifetime: same-line closure coverage requires LLVM columns, not a relaxed aggregate matcher. Capture freezes validated native bytes in the receipt; later analysis retains artifact validation without depending on DerivedData.
- Capture consistency: fingerprint result artifacts before context/export processing and again before receipt creation, rejecting changes between those reads.
- Native read isolation: a black-box per-file digest probe showed that `xcresulttool get test-results summary` creates a SQLite cache. Run that query on a disposable copy instead of excluding the new file from evidence hashing.
- Product identity: canonical project paths, compiler working/module/output paths and resolved executable paths corroborate target selection; same-basename projects and shared source files cannot substitute another product's evidence.
- Compiler omissions: native fixtures retain authored preview closures, unavailable initializers and an executing observed-property body even when LLVM emits no independent record. Do not discard inventory or borrow generated-function coverage to make a gate pass.
- Scoped evidence: LLVM source filters do not filter its function table. Retain whole relevant function records with their original filename indices and regions, omit unrelated records and invalid global totals, and corroborate selected evidence against xccov before freezing it.
- Native corroboration: account for wrapped line segments, adjacent subranges and machine variants with identical primary source spans. Reject secondary-source function evidence without corresponding file evidence; preserve original records for the unchanged core matcher.

Each accepted behavior is covered by a focused regression test. The complete local and CI gate is `./scripts/verify.sh`.

## Findings rejected or clarified

- Below-threshold baseline increases remain failures by design. Baseline mode is a strict no-regression ratchet, not merely an exemption list for existing above-threshold debt.
- Different LLVM region kinds at identical spans must not be blindly merged. Native precedence intentionally keeps the first kind; same-kind observations combine their counts.
- An external file alias resolving inside an explicitly selected root is allowed. Containment applies to the selected canonical source; the default file root still comes from the lexical parent.
- Capture command wrappers and PATH resolution remain within the documented trusted-command boundary. Receipts protect against accidental evidence mismatches; they do not attest to a hostile command or toolchain.

## Explicit boundaries

The readiness work adds compiler-backed active regions, source/artifact capture receipts, resolved Xcode target membership, genuine xcresult integration and independently audited upstream packages. Macro-generated declarations remain outside authored inventory. Receipts are unsigned and cannot establish a malicious command's truthfulness; coverage still says nothing about assertion quality. Exact platform/corpus support and failed attempts are recorded in docs/compatibility.md.
