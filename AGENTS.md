# swift-crap

A reusable Swift analysis engine and CLI that combine source callable complexity with measured compiler coverage.

## Workflow

Run `./scripts/init.sh` after cloning. Use feature branches and conventional commits. Run `./scripts/verify.sh` before declaring work complete. Test behavior through public boundaries before implementation. Unit, integration, and executable end-to-end tests are required.

## Architecture

Dependencies point inward: entities and scoring in CrapCore; use cases and capability protocols in CrapApplication; SwiftSyntax and coverage decoding in adapters; concrete wiring only in the CLI composition root. Manual dependency injection. No service locators, containers, speculative patterns, or global mutable state. A gateway implementation should be replaceable by changing that implementation and the composition root.

Use one cohesive type per production file. Default to the most restrictive access. Keep callers above callees, one abstraction level per function, and small methods. Prefer let, domain values, descriptive names, and enum states. No force unwraps or unchecked concurrency escapes in production.

## Readability

No explanatory source comments or documentation comments. Express intent through names, types, decomposition, and tests. SwiftPM's required tools-version directive and executable script shebangs are machine directives, not explanatory comments. Architecture and usage explanations belong in Markdown.

## Testing

Use Swift Testing. Prefer public behavior and state assertions to implementation-detail mocks. Fresh fixtures, one behavior per test, short intention-revealing names, helpers below tests. Exercise actual LLVM coverage in integration and CLI tests. Unknown, malformed, ambiguous, or missing required input fails explicitly. Never turn analysis failure into a clean gate.

## Reproducibility

Pin dependencies and version metric/report semantics. Stable relative paths and deterministic output ordering. Source positions are UTF-8 byte columns. Do not mutate analyzed projects or silently execute their tests. Test execution is an explicit external workflow. Do not add telemetry or network access to the analyzer.

## Commits

`<type>(<scope>): <imperative subject>`, lowercase subject, no period, at most 70 characters. Types: feat, fix, refactor, test, docs, chore, style, perf. Scopes: entities, use-cases, infra, app. One logical change per commit.
