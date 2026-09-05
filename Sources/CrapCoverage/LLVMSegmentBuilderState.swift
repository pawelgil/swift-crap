import CrapCore

struct LLVMSegmentBuilderState {
    var activeRegions: [LLVMRegion] = []
    var segments: [LLVMCoverageSegment] = []

    mutating func completeRegions(endingAtOrBefore position: SourcePosition) {
        let remaining = activeRegions.filter { $0.end > position }
        let completed = activeRegions.filter { $0.end <= position }.sorted { $0.end < $1.end }
        guard !completed.isEmpty else {
            return
        }
        activeRegions = remaining + completed
        completeRegions(from: remaining.count, nextPosition: position)
    }

    mutating func completeAllRegions() {
        guard !activeRegions.isEmpty else {
            return
        }
        activeRegions.sort { $0.end < $1.end }
        completeRegions(from: 0, nextPosition: nil)
    }

    mutating func startSegment(
        _ region: LLVMRegion,
        at position: SourcePosition,
        isRegionEntry: Bool,
        emitSkippedRegion: Bool = false,
    ) {
        let hasCount = !emitSkippedRegion && region.kind != 2
        if suppressesSegment(
            count: region.count,
            hasCount: hasCount,
            isRegionEntry: isRegionEntry,
            forced: emitSkippedRegion,
        ) {
            return
        }
        segments.append(LLVMCoverageSegment(
            position: position,
            count: hasCount ? region.count : 0,
            hasCount: hasCount,
            isRegionEntry: isRegionEntry,
            isGapRegion: hasCount && region.kind == 3,
        ))
    }

    private mutating func completeRegions(from first: Int, nextPosition: SourcePosition?) {
        emitCompletedTransitions(from: first, nextPosition: nextPosition)
        guard let last = activeRegions.last else {
            return
        }
        if first > 0, last.end != nextPosition {
            startSegment(activeRegions[first - 1], at: last.end, isRegionEntry: false)
        } else if first == 0, nextPosition == nil || nextPosition != last.end {
            startSegment(last, at: last.end, isRegionEntry: false, emitSkippedRegion: true)
        }
        activeRegions.removeSubrange(first...)
    }

    private mutating func emitCompletedTransitions(from first: Int, nextPosition: SourcePosition?) {
        guard first + 1 < activeRegions.count else {
            return
        }
        for index in (first + 1) ..< activeRegions.count {
            let position = activeRegions[index - 1].end
            if nextPosition == position {
                break
            }
            var completed = activeRegions[index]
            guard position != completed.end else {
                continue
            }
            if index + 1 < activeRegions.count {
                for later in activeRegions[(index + 1)...] where later.end == completed.end {
                    completed = later
                }
            }
            startSegment(completed, at: position, isRegionEntry: false)
        }
    }

    private func suppressesSegment(
        count: Int,
        hasCount: Bool,
        isRegionEntry: Bool,
        forced: Bool,
    ) -> Bool {
        guard let last = segments.last, !isRegionEntry, !forced else {
            return false
        }
        return last.hasCount == hasCount && last.count == count && !last.isRegionEntry
    }
}
