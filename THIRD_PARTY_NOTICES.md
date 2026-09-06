# Third-party notices

## LLVM coverage semantics

The coverage-region segmentation and line-counting implementation in `Sources/CrapCoverage/LLVMSegmentBuilder.swift`, `LLVMSegmentBuilderState.swift`, `LLVMCoverageSegment.swift`, and `LLVMLineCoverage.swift` adapts the algorithms in LLVM's `SegmentBuilder` and `LineCoverageStats` to Swift and this project's per-function import model.

LLVM Project, copyright LLVM contributors. Licensed under Apache License 2.0 with LLVM exceptions; the upstream license is reproduced in [LICENSES/LLVM.txt](LICENSES/LLVM.txt). The Swift adaptation decomposes the algorithm into value types and validates it through compiler-generated coverage tests.

Reference: [LLVM 21.1.0 CoverageMapping.cpp](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.0/llvm/lib/ProfileData/Coverage/CoverageMapping.cpp).

## SwiftSyntax

SwiftSyntax 603.0.2 is a pinned SwiftPM dependency, not copied source. Copyright Swift project contributors; Apache License 2.0 with Runtime Library Exception. Its notices and license are distributed with the dependency: [SwiftSyntax LICENSE.txt](https://github.com/swiftlang/swift-syntax/blob/603.0.2/LICENSE.txt).

`ConfiguredRegions+Position.swift` adapts SwiftIfConfig's region-boundary calculation to query parser diagnostic positions. The applicable SwiftSyntax license is reproduced in [LICENSES/SwiftSyntax.txt](LICENSES/SwiftSyntax.txt); this adaptation keeps original source positions while ignoring only compiler-unparsed regions.

## Swift Crypto

Swift Crypto 4.5.2 supplies SHA-256. It is a pinned SwiftPM dependency under Apache License 2.0 with Runtime Library Exception: [Swift Crypto LICENSE.txt](https://github.com/apple/swift-crypto/blob/4.5.2/LICENSE.txt). Its bundled BoringSSL and other notices remain in the dependency. Swift ASN.1 1.7.2 is transitively pinned in `Package.resolved`: [Swift ASN.1 LICENSE.txt](https://github.com/apple/swift-asn1/blob/1.7.2/LICENSE.txt).

Compatibility tests fetch separately licensed upstream repositories at pinned revisions. They are not incorporated into this project's production source. See the compatibility manifest and each upstream checkout's license before redistribution.
