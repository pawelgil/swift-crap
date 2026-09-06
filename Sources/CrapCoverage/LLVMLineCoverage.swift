import CrapCore

package struct LLVMLineCoverage {
    static let maximumExpandedLinesPerFunction = 1_000_000

    package init() {}

    package func lines(from regions: [LLVMRegion]) throws -> [CoverageLine] {
        let segments = try LLVMSegmentBuilder().build(from: regions)
        guard let firstLine = segments.first?.position.line,
              let lastLine = segments.last?.position.line
        else {
            return []
        }
        let lineCount = try expandedLineCount(first: firstLine, last: lastLine)
        var wrapped: LLVMCoverageSegment?
        var segmentIndex = 0
        var result: [CoverageLine] = []
        result.reserveCapacity(lineCount)
        for offset in 0 ..< lineCount {
            let (line, overflow) = firstLine.addingReportingOverflow(offset)
            guard !overflow else {
                throw CoverageDecodingError.oversizedLineRange(
                    maximumExpandedLines: Self.maximumExpandedLinesPerFunction,
                )
            }
            let lineStart = segmentIndex
            while segmentIndex < segments.count, segments[segmentIndex].position.line == line {
                segmentIndex += 1
            }
            let onLine = segments[lineStart ..< segmentIndex]
            if let coverage = lineCoverage(line: line, segments: onLine, wrapped: wrapped) {
                result.append(coverage)
            }
            if let last = onLine.last {
                wrapped = last
            }
        }
        return result
    }

    private func expandedLineCount(first: Int, last: Int) throws -> Int {
        let (distance, subtractionOverflow) = last.subtractingReportingOverflow(first)
        let (count, additionOverflow) = distance.addingReportingOverflow(1)
        guard !subtractionOverflow,
              !additionOverflow,
              distance >= 0,
              count <= Self.maximumExpandedLinesPerFunction
        else {
            throw CoverageDecodingError.oversizedLineRange(
                maximumExpandedLines: Self.maximumExpandedLinesPerFunction,
            )
        }
        return count
    }

    private func lineCoverage(
        line: Int,
        segments: ArraySlice<LLVMCoverageSegment>,
        wrapped: LLVMCoverageSegment?,
    ) -> CoverageLine? {
        let entries = segments.filter { !$0.isGapRegion && $0.hasCount && $0.isRegionEntry }
        let startsSkipped = segments.first.map { !$0.hasCount && $0.isRegionEntry } ?? false
        let hasWrappedCount = wrapped?.hasCount == true
        let mapped = (!startsSkipped && (hasWrappedCount || !entries.isEmpty))
            || segments.contains { $0.isRegionEntry && $0.hasCount }
        guard mapped else {
            return nil
        }
        let entryCount = entries.map(\.count).max() ?? 0
        let executionCount = max(wrapped?.count ?? 0, entryCount)
        return CoverageLine(line: line, covered: executionCount > 0)
    }
}
