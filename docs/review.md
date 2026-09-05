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

Each accepted behavior is covered by a focused regression test. The complete local and CI gate is `./scripts/verify.sh`.

## Findings rejected or clarified

- Below-threshold baseline increases remain failures by design. Baseline mode is a strict no-regression ratchet, not merely an exemption list for existing above-threshold debt.
- Different LLVM region kinds at identical spans must not be blindly merged. Native precedence intentionally keeps the first kind; same-kind observations combine their counts.
- An external file alias resolving inside an explicitly selected root is allowed. Containment applies to the selected canonical source; the default file root still comes from the lexical parent.

## Explicit boundaries

Xcode target discovery uses a source manifest. Macro-generated declarations and build-specific conditional selection are not synthesized. xccov validation uses schema fixtures, while LLVM integration uses real compiler exports. Coverage provenance and test assertion quality remain the caller's responsibility. These are documented capabilities, not silently inferred guarantees.
