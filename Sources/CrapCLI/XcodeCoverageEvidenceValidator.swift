import CrapCore
import CrapCoverage
import Foundation

struct XcodeCoverageEvidenceValidator {
    func validate(
        _ data: Data,
        files: [File],
        archive: [String: [ArchiveLine]],
        sources: Set<String>,
    ) throws {
        let native = try decode(data)
        guard native.type == "llvm.coverage.json.export",
              ["2", "3"].contains(native.version.split(separator: ".").first.map(String.init)),
              !native.data.isEmpty
        else {
            throw XcodeNativeCoverageExportError.invalidEvidence("LLVM coverage has unsupported schema")
        }
        let nativeFiles = try uniqueFiles(
            native.data.flatMap(\.files).filter { try sources.contains(CanonicalPath().resolve($0.filename)) },
            path: \.filename,
            label: "LLVM",
        )
        let reportFiles = try uniqueFiles(
            files.filter { try sources.contains(CanonicalPath().resolve($0.path)) },
            path: \.path,
            label: "xccov report",
        )
        let archiveFiles = try uniqueArchive(archive.filter {
            try sources.contains(CanonicalPath().resolve($0.key))
        })
        let nativeFunctions = try functions(native, sources: sources)
        for source in sources {
            let reportFile = reportFiles[source]
            let nativeFile = nativeFiles[source]
            let archiveLines = archiveFiles[source]
            guard (reportFile == nil) == (nativeFile == nil),
                  (reportFile == nil) == (archiveLines == nil)
            else {
                throw XcodeNativeCoverageExportError.invalidEvidence("coverage presence differs for \(source)")
            }
            guard let reportFile, let nativeFile, let archiveLines else {
                guard nativeFunctions[source]?.isEmpty != false else {
                    throw XcodeNativeCoverageExportError.invalidEvidence(
                        "function coverage has no file evidence for \(source)",
                    )
                }
                continue
            }
            guard reportFile.coveredLines == nativeFile.summary.lines.covered,
                  reportFile.executableLines == nativeFile.summary.lines.count
            else {
                throw XcodeNativeCoverageExportError.invalidEvidence("file totals differ for \(source)")
            }
            try validateLines(archiveLines, segments: nativeFile.segments, source: source)
            guard aggregates(reportFile.functions) == aggregates(nativeFunctions[source] ?? []) else {
                throw XcodeNativeCoverageExportError.invalidEvidence("function aggregates differ for \(source)")
            }
        }
    }

    private func aggregates(_ functions: [Function]) -> [FunctionAggregate: Int] {
        functions.reduce(into: [:]) { result, function in
            let aggregate = FunctionAggregate(
                anchorLine: function.anchorLine,
                coveredLines: function.coveredLines,
                executableLines: function.executableLines,
            )
            result[aggregate, default: 0] += 1
        }
    }

    private func functions(_ document: LLVMDocument, sources: Set<String>) throws -> [String: [Function]] {
        var grouped: [String: [FunctionIdentity: [LLVMRegion]]] = [:]
        for function in document.data.flatMap(\.functions) {
            guard function.count >= 0, !function.filenames.isEmpty else {
                throw XcodeNativeCoverageExportError.invalidEvidence("LLVM function has invalid metadata")
            }
            for (index, filename) in function.filenames.enumerated() {
                let path = try CanonicalPath().resolve(filename)
                guard sources.contains(path) else { continue }
                let regions = try function.regions.compactMap { region -> LLVMRegion? in
                    guard region.fileIndex == index, region.kind <= 3 else { return nil }
                    return try region.validated()
                }
                let code = regions.filter { $0.kind == 0 }
                guard let start = code.map(\.start).min(), let end = code.map(\.end).max() else { continue }
                let identity = FunctionIdentity(end: end, start: start)
                grouped[path, default: [:]][identity] = merge(
                    grouped[path, default: [:]][identity],
                    with: regions,
                )
            }
        }
        return try grouped.mapValues { groups in
            try groups.values.map { regions in
                let code = regions.filter { $0.kind == 0 }
                guard let anchor = code.map(\.start).min() else {
                    throw XcodeNativeCoverageExportError.invalidEvidence("LLVM function has no code region")
                }
                let lines = try LLVMLineCoverage().lines(from: regions)
                return Function(
                    anchorLine: anchor.line,
                    coveredLines: lines.count(where: \.covered),
                    executableLines: lines.count,
                )
            }
        }
    }

    private func merge(_ existing: [LLVMRegion]?, with regions: [LLVMRegion]) -> [LLVMRegion] {
        var merged: [RegionIdentity: LLVMRegion] = [:]
        for region in (existing ?? []) + regions {
            let identity = RegionIdentity(region)
            let count = max(merged[identity]?.count ?? 0, region.count)
            merged[identity] = LLVMRegion(
                start: region.start,
                end: region.end,
                count: count,
                fileIndex: region.fileIndex,
                kind: region.kind,
            )
        }
        return merged.values.sorted {
            ($0.start, $0.end, $0.kind) < ($1.start, $1.end, $1.kind)
        }
    }

    private func uniqueFiles<Value>(
        _ values: [Value],
        path: KeyPath<Value, String>,
        label: String,
    ) throws -> [String: Value] {
        var result: [String: Value] = [:]
        for value in values {
            let key = try CanonicalPath().resolve(value[keyPath: path])
            guard result.updateValue(value, forKey: key) == nil else {
                throw XcodeNativeCoverageExportError.invalidEvidence("\(label) repeats file \(key)")
            }
        }
        return result
    }

    private func uniqueArchive(_ archive: [String: [ArchiveLine]]) throws -> [String: [ArchiveLine]] {
        var result: [String: [ArchiveLine]] = [:]
        for (path, lines) in archive {
            let key = try CanonicalPath().resolve(path)
            guard result.updateValue(lines, forKey: key) == nil else {
                throw XcodeNativeCoverageExportError.invalidEvidence("xccov archive repeats file \(key)")
            }
        }
        return result
    }

    private func validateLines(_ archive: [ArchiveLine], segments: [Segment], source: String) throws {
        var expected: [Int: Int] = [:]
        var observedLines: Set<Int> = []
        for line in archive {
            guard line.line > 0, observedLines.insert(line.line).inserted else {
                throw XcodeNativeCoverageExportError.invalidEvidence("xccov archive has invalid or repeated line")
            }
            for range in line.subranges ?? [] where range.column <= 0 || range.length < 0 || range.executionCount < 0 {
                throw XcodeNativeCoverageExportError.invalidEvidence("xccov archive has invalid subrange")
            }
            guard line.isExecutable else { continue }
            guard let count = line.executionCount else {
                throw XcodeNativeCoverageExportError.invalidEvidence("executable xccov line has no count")
            }
            guard count >= 0 else {
                throw XcodeNativeCoverageExportError.invalidEvidence("executable xccov line has invalid count")
            }
            expected[line.line] = count
        }
        let actual = try lineCounts(segments, through: expected.keys.max())
        guard expected.allSatisfy({ actual[$0.key] == $0.value }) else {
            throw XcodeNativeCoverageExportError.invalidEvidence("line execution counts differ for \(source)")
        }
        for line in archive where line.isExecutable {
            let subranges = line.subranges ?? []
            for range in subranges {
                guard executionCount(line: line.line, column: range.column, segments: segments)
                    == range.executionCount
                else {
                    throw XcodeNativeCoverageExportError
                        .invalidEvidence("subrange execution differs for \(source):\(line.line):\(range.column)")
                }
                let (endColumn, overflow) = range.column.addingReportingOverflow(range.length)
                let endCount = subranges.first(where: { $0.column == endColumn })?.executionCount
                    ?? line.executionCount
                guard !overflow,
                      range.length == 0 || segments.contains(where: {
                          $0.line == line.line
                              && $0.column == endColumn
                              && (!$0.hasCount || $0.count == endCount)
                      })
                else {
                    throw XcodeNativeCoverageExportError
                        .invalidEvidence("subrange extent differs for \(source):\(line.line):\(range.column)")
                }
            }
        }
    }

    private func executionCount(line: Int, column: Int, segments: [Segment]) -> Int? {
        segments.last(where: {
            $0.line < line || $0.line == line && $0.column <= column
        }).flatMap { $0.hasCount ? $0.count : nil }
    }

    private func lineCounts(_ segments: [Segment], through lastExpectedLine: Int?) throws -> [Int: Int] {
        guard let firstLine = segments.first?.line,
              let lastLine = lastExpectedLine,
              firstLine <= lastLine
        else { return [:] }
        let (distance, overflow) = lastLine.subtractingReportingOverflow(firstLine)
        guard !overflow, distance <= 1_000_000 else {
            throw XcodeNativeCoverageExportError.invalidEvidence("LLVM line range exceeds 1000000 lines")
        }
        let grouped = Dictionary(grouping: segments, by: \.line)
        var wrapped: Segment?
        var result: [Int: Int] = [:]
        for line in firstLine ... lastLine {
            let current = grouped[line] ?? []
            let entries = current.filter { !$0.isGap && $0.hasCount && $0.isRegionEntry }
            let startsSkipped = current.first.map { !$0.hasCount && $0.isRegionEntry } ?? false
            if !startsSkipped, wrapped?.hasCount == true || !entries.isEmpty {
                result[line] = max(wrapped?.count ?? 0, entries.map(\.count).max() ?? 0)
            } else if current.contains(where: { $0.isRegionEntry && $0.hasCount }) {
                result[line] = entries.map(\.count).max() ?? 0
            }
            if let last = current.last { wrapped = last }
        }
        return result
    }

    private func decode(_ data: Data) throws -> LLVMDocument {
        do { return try JSONDecoder().decode(LLVMDocument.self, from: data) }
        catch { throw XcodeNativeCoverageExportError.invalidEvidence("cannot decode LLVM coverage: \(error)") }
    }

    struct File {
        let coveredLines: Int
        let executableLines: Int
        let functions: [Function]
        let path: String
    }

    struct Function {
        let anchorLine: Int
        let coveredLines: Int
        let executableLines: Int
    }

    struct ArchiveLine: Decodable {
        let executionCount: Int?
        let isExecutable: Bool
        let line: Int
        let subranges: [ArchiveSubrange]?
    }

    struct ArchiveSubrange: Decodable {
        let column: Int
        let executionCount: Int
        let length: Int
    }

    private struct LLVMDocument: Decodable {
        let data: [LLVMUnit]
        let type: String
        let version: String
    }

    private struct LLVMUnit: Decodable {
        let files: [LLVMFile]
        let functions: [LLVMFunction]
    }

    private struct LLVMFile: Decodable {
        let filename: String
        let segments: [Segment]
        let summary: LLVMSummary
    }

    private struct LLVMSummary: Decodable {
        let lines: LLVMLineSummary
    }

    private struct LLVMLineSummary: Decodable {
        let count: Int
        let covered: Int
    }

    private struct LLVMFunction: Decodable {
        let count: Int
        let filenames: [String]
        let regions: [FunctionRegion]
    }

    private struct FunctionRegion: Decodable {
        let count: Int
        let endColumn: Int
        let endLine: Int
        let fileIndex: Int
        let kind: Int
        let startColumn: Int
        let startLine: Int

        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            startLine = try values.decode(Int.self)
            startColumn = try values.decode(Int.self)
            endLine = try values.decode(Int.self)
            endColumn = try values.decode(Int.self)
            count = try values.decode(Int.self)
            fileIndex = try values.decode(Int.self)
            _ = try values.decode(Int.self)
            kind = try values.decode(Int.self)
        }

        func validated() throws -> LLVMRegion {
            let start = SourcePosition(line: startLine, column: startColumn)
            let end = SourcePosition(line: endLine, column: endColumn)
            guard startLine > 0,
                  startColumn > 0,
                  endLine > 0,
                  endColumn > 0,
                  start < end,
                  count >= 0,
                  fileIndex >= 0,
                  kind >= 0,
                  kind <= 4
            else {
                throw XcodeNativeCoverageExportError.invalidEvidence("LLVM function has invalid region")
            }
            return LLVMRegion(start: start, end: end, count: count, fileIndex: fileIndex, kind: kind)
        }
    }

    private struct FunctionAggregate: Hashable {
        let anchorLine: Int
        let coveredLines: Int
        let executableLines: Int
    }

    private struct FunctionIdentity: Hashable {
        let end: SourcePosition
        let start: SourcePosition
    }

    private struct RegionIdentity: Hashable {
        let end: SourcePosition
        let kind: Int
        let start: SourcePosition

        init(_ region: LLVMRegion) {
            end = region.end
            kind = region.kind
            start = region.start
        }
    }

    private struct Segment: Decodable {
        let line: Int
        let column: Int
        let count: Int
        let hasCount: Bool
        let isRegionEntry: Bool
        let isGap: Bool

        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            line = try values.decode(Int.self)
            column = try values.decode(Int.self)
            count = try values.decode(Int.self)
            hasCount = try values.decode(Bool.self)
            isRegionEntry = try values.decode(Bool.self)
            isGap = try values.decode(Bool.self)
            guard line > 0, column > 0, count >= 0 else {
                throw DecodingError.dataCorruptedError(in: values, debugDescription: "invalid LLVM segment")
            }
        }
    }
}
