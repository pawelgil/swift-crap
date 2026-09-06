# Contributing

Start with [AGENTS.md](AGENTS.md), the [behavioral contract](CONTRACT.md), and [metric rules](docs/metrics.md). Changes must preserve the distinction between measured coverage, explicitly assumed zero coverage, and missing evidence.

## Development

Use Swift 6.3, Node.js 22 or newer, and matching Swift/LLVM tools. macOS integration additionally requires a full Xcode installation. After cloning or creating a worktree, run `./scripts/init.sh`. Run `./scripts/verify.sh` before submitting a change. The macOS gate includes a real XCTest result bundle; Linux verifies the portable LLVM path. Neither platform substitutes fixtures for all compiler tests.

Create a feature branch and open a pull request. Use `<type>(<scope>): <imperative lowercase subject>` commits, under 70 characters. Keep unrelated changes separate. Do not edit generated dependency checkouts or omit `Package.resolved` when changing dependencies.

## Behavioral changes

Begin with a failing public-behavior test. Add a unit test for the rule, a real compiler integration test when coverage/compiler semantics change, and an executable E2E test for user-visible behavior. Compare coverage against native `llvm-cov` or `xccov`, not another path through our decoder. Record counterexamples from upstream projects and pin their revisions. Preserve all failures in compatibility notes until resolved.

Keep dependency direction inward, use narrow capability protocols and manual injection, and keep production types cohesive. Prefer descriptive names and extraction to explanatory comments. Required tool directives and license notices are exceptions. Do not add telemetry, implicit test execution, network access in analysis, or silent fallback to zero coverage.

## Dependencies and releases

Update one dependency deliberately, retain upstream notices, run the full platform gate and compatibility harness, and inspect source/coverage semantic changes. Do not automatically accept dependency upgrades on a green build alone. Any metric-rule change requires a new metric identifier and baseline migration guidance. Document public behavior changes in [CHANGELOG.md](CHANGELOG.md).

See [release readiness](docs/readiness-contract.md) for the publication checklist. Publication and repository visibility changes are owner decisions.
