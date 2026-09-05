import CrapCore

struct LLVMCoverageSegment {
    let position: SourcePosition
    let count: Int
    let hasCount: Bool
    let isRegionEntry: Bool
    let isGapRegion: Bool
}
