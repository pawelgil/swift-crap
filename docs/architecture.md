# Architecture

## Behavioral boundaries

The executable acceptance tests define source selection, report contents, exit codes, repeatability, and baseline behavior. Compiler integration tests generate their own instrumented binaries and compare coverage with LLVM. Unit tests isolate mathematical rules, syntax semantics, import validation, and application orchestration. Implementation boundaries follow these observable responsibilities.

| Module | Responsibility | Dependencies |
| --- | --- | --- |
| CrapCore | Callable/coverage values, reconciliation, scoring, gate evaluation | Foundation |
| CrapApplication | Select/read/analyze/import/score use case and I/O capabilities | CrapCore |
| CrapSyntax | SwiftSyntax callable inventory and decision counting | CrapCore, SwiftSyntax, SwiftParser |
| CrapCoverage | LLVM/xccov decoding and normalization | CrapCore |
| CrapCLI | Arguments, filesystem/package adapters, rendering, concrete composition | Application and adapters |

External capabilities are injected through narrow protocols. The engine consumes values and has no build or test execution responsibility. The CLI composition root selects concrete adapters. Replacing source parsing changes its adapter and composition; replacing coverage decoding leaves the scoring rules intact.

No container, service locator, global mutable registry, asynchronous fire-and-forget task, or compiler plugin is required. Synchronous CLI I/O keeps the initial design small and predictable. Swift Testing fixtures are independent and process captures use temporary files to avoid pipe-buffer deadlocks.

## Why source syntax

SwiftSyntax preserves authored declarations and exact UTF-8 source positions. It enables separate ownership for functions, accessors, and closures. SIL and LLVM control flow include compiler lowering, generated functions, and optimization effects; those are useful for compiler analysis but do not define this tool's source-level metric.

Compiler coverage remains the authority for observed execution. LLVM function records preserve ownership even for same-line callables. Xcode function aggregates need stricter matching because their source anchors lack columns. Ambiguity is an analysis failure.

LLVM line coverage is reconstructed from per-function regions using the upstream segment and line-stat algorithms. The implementation follows LLVM's [SegmentBuilder](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.0/llvm/lib/ProfileData/Coverage/CoverageMapping.cpp) and [LineCoverageStats](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.0/llvm/lib/ProfileData/Coverage/CoverageMapping.cpp), with the data model grounded in the [source-based coverage documentation](https://clang.llvm.org/docs/SourceBasedCodeCoverage.html). This preserves LLVM's ordering, region combination, gap, skipped-region, wrapped-segment, and maximum region-entry count semantics instead of approximating covered lines from overlapping source ranges.

## Reproducibility

Dependencies and metric semantics are pinned. Reports omit clocks, absolute source paths, and environment-dependent ordering. Baseline comparisons use callable identities rather than line numbers. Files are normalized relative to the explicit analysis root. Missing observations are distinguishable from recorded zero execution.

Source revision provenance must be enforced by the caller's build pipeline. Raw LLVM/xccov JSON cannot establish that an artifact belongs to the current checkout. This engine does not infer freshness from modification times.

## Scope decisions

A project is a source tree, a package is SwiftPM membership, a package target is exact target membership, and a file is explicit selection. Xcode and custom build systems use a target source manifest. This keeps build-system assumptions in adapters and makes the selected files reviewable.

The v1 CLI provides JSON and text. SARIF, automatic Xcode project parsing, macro expansion, compiler-configuration-aware conditional evaluation, and compiler-USR enrichment are possible later adapters/features; none is required to compute and gate the current metric.
