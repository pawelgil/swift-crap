import CrapCore

struct LLVMCoverageDecoder {
    func decode(_ document: [String: Any]) throws -> CoverageImport {
        guard try CoverageJSON.string(document["type"]) == "llvm.coverage.json.export" else {
            throw CoverageDecodingError.unsupportedSchema
        }
        try validate(version: CoverageJSON.string(document["version"]))
        let units = try CoverageJSON.dictionaries(document["data"])
        guard !units.isEmpty else {
            throw CoverageDecodingError.malformedInput
        }
        let records = try units.flatMap(decodeUnit).sorted(by: recordOrder)
        return CoverageImport(records: records, format: "llvm")
    }

    private func validate(version: String) throws {
        guard let major = version.split(separator: ".").first,
              Int(major) != nil
        else {
            throw CoverageDecodingError.malformedInput
        }
        guard major == "2" || major == "3" else {
            throw CoverageDecodingError.unsupportedLLVMVersion(version)
        }
    }

    private func decodeUnit(_ unit: [String: Any]) throws -> [CoverageRecord] {
        let functions = try CoverageJSON.dictionaries(unit["functions"])
        return try functions.flatMap(decodeFunction)
    }

    private func decodeFunction(_ function: [String: Any]) throws -> [CoverageRecord] {
        let name = try CoverageJSON.string(function["name"])
        _ = try nonnegative(function["count"])
        let filenames = try CoverageJSON.array(function["filenames"]).map(CoverageJSON.string)
        guard !filenames.isEmpty else {
            throw CoverageDecodingError.malformedInput
        }
        let regions = try CoverageJSON.array(function["regions"])
            .map { try decodeRegion($0, fileCount: filenames.count) }
        let grouped = Dictionary(grouping: regions.filter { $0.kind <= 3 }, by: \.fileIndex)
        return try grouped.map { index, regions in
            try makeRecord(name: name, file: filenames[index], regions: regions)
        }.compactMap(\.self)
    }

    private func decodeRegion(_ value: Any, fileCount: Int) throws -> LLVMRegion {
        let values = try CoverageJSON.array(value)
        guard values.count >= 8 else {
            throw CoverageDecodingError.malformedInput
        }
        let region = try LLVMRegion(
            start: SourcePosition(line: positive(values[0]), column: positive(values[1])),
            end: SourcePosition(line: positive(values[2]), column: positive(values[3])),
            count: nonnegative(values[4]),
            fileIndex: nonnegative(values[5]),
            kind: nonnegative(values[7]),
        )
        guard region.start < region.end,
              region.fileIndex < fileCount,
              region.kind <= 4
        else {
            throw CoverageDecodingError.malformedInput
        }
        _ = try nonnegative(values[6])
        return region
    }

    private func positive(_ value: Any?) throws -> Int {
        let number = try CoverageJSON.integer(value)
        guard number > 0 else {
            throw CoverageDecodingError.malformedInput
        }
        return number
    }

    private func nonnegative(_ value: Any?) throws -> Int {
        let number = try CoverageJSON.integer(value)
        guard number >= 0 else {
            throw CoverageDecodingError.malformedInput
        }
        return number
    }

    private func makeRecord(name: String, file: String, regions: [LLVMRegion]) throws -> CoverageRecord? {
        let codeRegions = regions.filter { $0.kind == 0 }
        guard let start = codeRegions.map(\.start).min(),
              let end = codeRegions.map(\.end).max()
        else {
            return nil
        }
        return try CoverageRecord(
            file: CoveragePath.normalize(file),
            name: name,
            span: SourceSpan(start: start, end: end),
            anchor: start,
            lines: LLVMLineCoverage().lines(from: regions),
            coveredLines: nil,
            executableLines: nil,
        )
    }

    private func recordOrder(_ lhs: CoverageRecord, _ rhs: CoverageRecord) -> Bool {
        (lhs.file, lhs.anchor, lhs.name) < (rhs.file, rhs.anchor, rhs.name)
    }
}
