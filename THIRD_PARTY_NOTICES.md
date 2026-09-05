# Third-party notices

## LLVM coverage semantics

The coverage-region segmentation and line-counting implementation in `Sources/CrapCoverage/LLVMSegmentBuilder.swift`, `LLVMSegmentBuilderState.swift`, `LLVMCoverageSegment.swift`, and `LLVMLineCoverage.swift` adapts the algorithms in LLVM's `SegmentBuilder` and `LineCoverageStats` to Swift and this project's per-function import model.

LLVM Project, copyright LLVM contributors. Licensed under Apache License 2.0 with LLVM exceptions; the upstream license is reproduced in [LICENSES/LLVM.txt](LICENSES/LLVM.txt). The Swift adaptation decomposes the algorithm into value types and validates it through compiler-generated coverage tests.

Reference: [LLVM 21.1.0 CoverageMapping.cpp](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.0/llvm/lib/ProfileData/Coverage/CoverageMapping.cpp).

## SwiftSyntax

SwiftSyntax 603.0.2 is a pinned SwiftPM dependency, not copied source. Copyright Swift project contributors; Apache License 2.0 with Runtime Library Exception. Its notices and license are distributed with the dependency: [SwiftSyntax LICENSE.txt](https://github.com/swiftlang/swift-syntax/blob/603.0.2/LICENSE.txt).
