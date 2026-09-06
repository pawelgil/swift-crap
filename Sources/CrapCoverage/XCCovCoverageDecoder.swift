import CrapCore

struct XCCovCoverageDecoder {
    func decode(_ document: [String: Any]) throws -> CoverageImport {
        try validateSummary(document)
        let targets = try CoverageJSON.dictionaries(document["targets"])
        let records = try targets.flatMap(decodeTarget).sorted(by: recordOrder)
        return CoverageImport(records: records, format: "xccov")
    }

    private func decodeTarget(_ target: [String: Any]) throws -> [CoverageRecord] {
        _ = try CoverageJSON.string(target["name"])
        try validateSummary(target)
        let files = try CoverageJSON.dictionaries(target["files"])
        return try files.flatMap(decodeFile)
    }

    private func decodeFile(_ file: [String: Any]) throws -> [CoverageRecord] {
        try validateSummary(file)
        let path = try filePath(file)
        let functions = try CoverageJSON.dictionaries(file["functions"])
        return try functions.map { try decodeFunction($0, file: path) }
    }

    private func filePath(_ file: [String: Any]) throws -> String {
        if let path = file["path"] {
            return try CoverageJSON.string(path)
        }
        return try CoverageJSON.string(file["name"])
    }

    private func decodeFunction(_ function: [String: Any], file: String) throws -> CoverageRecord {
        try validateSummary(function)
        let name = try CoverageJSON.string(function["name"])
        let line = try CoverageJSON.integer(function["lineNumber"])
        let executionCount = try CoverageJSON.integer(function["executionCount"])
        guard line > 0, executionCount >= 0 else {
            throw CoverageDecodingError.malformedInput
        }
        return try CoverageRecord(
            file: CoveragePath.normalize(file),
            name: name,
            span: nil,
            anchor: SourcePosition(line: line, column: 1),
            lines: nil,
            coveredLines: CoverageJSON.integer(function["coveredLines"]),
            executableLines: CoverageJSON.integer(function["executableLines"]),
        )
    }

    private func validateSummary(_ object: [String: Any]) throws {
        let covered = try CoverageJSON.integer(object["coveredLines"])
        let executable = try CoverageJSON.integer(object["executableLines"])
        let fraction = try CoverageJSON.double(object["lineCoverage"])
        guard covered >= 0,
              executable >= 0,
              covered <= executable,
              fraction.isFinite,
              (0 ... 1).contains(fraction)
        else {
            throw CoverageDecodingError.invalidCounts
        }
        let expected = executable == 0 ? 0 : Double(covered) / Double(executable)
        guard abs(fraction - expected) <= 0.000_000_001 else {
            throw CoverageDecodingError.invalidCounts
        }
    }

    private func recordOrder(_ lhs: CoverageRecord, _ rhs: CoverageRecord) -> Bool {
        (lhs.file, lhs.anchor, lhs.name) < (rhs.file, rhs.anchor, rhs.name)
    }
}
