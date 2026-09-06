struct LLVMSegmentBuilder {
    func build(from input: [LLVMRegion]) throws -> [LLVMCoverageSegment] {
        let regions = try combinedRegions(input)
        var state = LLVMSegmentBuilderState()
        for (index, region) in regions.enumerated() {
            state.completeRegions(endingAtOrBefore: region.start)
            if index + 1 == regions.count || region.start != regions[index + 1].start {
                state.startSegment(region, at: region.start, isRegionEntry: region.kind != 3)
            }
            state.activeRegions.append(region)
        }
        state.completeAllRegions()
        return state.segments
    }

    private func combinedRegions(_ input: [LLVMRegion]) throws -> [LLVMRegion] {
        let sorted = input.enumerated().sorted { lhs, rhs in
            regionOrder(lhs.element, rhs.element, lhsOffset: lhs.offset, rhsOffset: rhs.offset)
        }.map(\.element)
        var result: [LLVMRegion] = []
        for region in sorted {
            if let previous = result.last,
               previous.start == region.start,
               previous.end == region.end
            {
                if previous.kind == region.kind {
                    result[result.count - 1] = try combined(previous, region)
                }
            } else {
                result.append(region)
            }
        }
        return result
    }

    private func regionOrder(
        _ lhs: LLVMRegion,
        _ rhs: LLVMRegion,
        lhsOffset: Int,
        rhsOffset: Int,
    ) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end > rhs.end
        }
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return lhsOffset < rhsOffset
    }

    private func combined(_ lhs: LLVMRegion, _ rhs: LLVMRegion) throws -> LLVMRegion {
        let (count, overflow) = lhs.count.addingReportingOverflow(rhs.count)
        guard !overflow else {
            throw CoverageDecodingError.invalidCounts
        }
        return LLVMRegion(
            start: lhs.start,
            end: lhs.end,
            count: count,
            fileIndex: lhs.fileIndex,
            kind: lhs.kind,
        )
    }
}
