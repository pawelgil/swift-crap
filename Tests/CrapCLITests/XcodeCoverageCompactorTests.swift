@testable import CrapCLI
import CrapCoverage
import Foundation
import Testing

struct XcodeCoverageCompactorTests {
    @Test func `drops unrelated file and function records`() throws {
        let fixture = try CompactorFixture()
        defer { fixture.remove() }
        let selectedFunction = function(name: "selected()", filenames: [fixture.selected.path])
        let unrelatedFunction = function(name: "unrelated()", filenames: [fixture.unrelated.path])
        let data = try document(
            files: [file(fixture.selected.path), file(fixture.unrelated.path)],
            functions: [selectedFunction, unrelatedFunction],
        )

        let result = try XcodeCoverageCompactor().compact(data, sources: [fixture.selected.path])
        let unit = try decodedUnit(result)

        #expect(try filenames(in: unit) == [fixture.selected.path])
        #expect(try functionNames(in: unit) == ["selected()"])
    }

    @Test func `retains whole function when selected filename is secondary`() throws {
        let fixture = try CompactorFixture()
        defer { fixture.remove() }
        let expected = function(
            name: "shared()",
            count: 7,
            filenames: [fixture.unrelated.path, fixture.selected.path],
            regions: [
                [2, 3, 2, 12, 0, 0, 0, 0],
                [8, 4, 8, 18, 7, 1, 0, 0],
            ],
            extra: ["unknown": ["nested": [3, 2, 1]]],
        )
        let data = try document(
            files: [file(fixture.unrelated.path), file(fixture.selected.path)],
            functions: [expected],
        )

        let result = try XcodeCoverageCompactor().compact(data, sources: [fixture.selected.path])
        let unit = try decodedUnit(result)
        let retained = try #require((unit["functions"] as? [[String: Any]])?.first)
        let coverage = try CompilerCoverageDecoder().decode(result)

        #expect((retained as NSDictionary).isEqual(to: expected))
        #expect(try filenames(in: unit) == [fixture.selected.path])
        #expect(coverage.records.contains { record in
            record.file == fixture.selected.path && record.name == "shared()"
        })
    }

    @Test func `serialization is deterministic`() throws {
        let firstInput = Data(
            #"{"version":"2.0.1","type":"llvm.coverage.json.export","data":[{"zeta":true,"functions":[],"files":[],"alpha":"value"}]}"#
                .utf8,
        )
        let secondInput = Data(
            #"{"data":[{"alpha":"value","files":[],"functions":[],"zeta":true}],"type":"llvm.coverage.json.export","version":"2.0.1"}"#
                .utf8,
        )
        let sut = XcodeCoverageCompactor()

        let first = try sut.compact(firstInput, sources: [])
        let second = try sut.compact(secondInput, sources: [])

        #expect(first == second)
    }

    @Test func `preserves integers larger than exact double precision`() throws {
        let fixture = try CompactorFixture()
        defer { fixture.remove() }
        let large = Int64(9_007_199_254_740_993)
        let data = try document(
            files: [file(fixture.selected.path)],
            functions: [function(
                name: "large()",
                count: large,
                filenames: [fixture.selected.path],
                regions: [[1, 1, 1, 2, large, 0, 0, 0]],
            )],
        )

        let result = try XcodeCoverageCompactor().compact(data, sources: [fixture.selected.path])
        let unit = try decodedUnit(result)
        let retained = try #require((unit["functions"] as? [[String: Any]])?.first)
        let count = try #require(retained["count"] as? NSNumber)
        let encoded = try #require(String(data: result, encoding: .utf8))

        #expect(count.int64Value == large)
        #expect(encoded.contains(String(large)))
    }

    @Test func `rejects malformed unit shape`() throws {
        let data = try JSONSerialization.data(withJSONObject: ["data": [[:]]])

        #expect(throws: XcodeNativeCoverageExportError.invalidEvidence(
            "LLVM coverage has invalid unit structure",
        )) {
            try XcodeCoverageCompactor().compact(data, sources: [])
        }
    }

    @Test func `rejects malformed file shape`() throws {
        let data = try document(files: [["unexpected": "value"]], functions: [])

        #expect(throws: XcodeNativeCoverageExportError.invalidEvidence(
            "LLVM coverage has invalid file structure",
        )) {
            try XcodeCoverageCompactor().compact(data, sources: [])
        }
    }

    @Test func `rejects malformed function shape`() throws {
        let data = try document(files: [], functions: [["name": "missing filenames"]])

        #expect(throws: XcodeNativeCoverageExportError.invalidEvidence(
            "LLVM coverage has invalid function structure",
        )) {
            try XcodeCoverageCompactor().compact(data, sources: [])
        }
    }

    @Test func `rejects malformed function filename`() throws {
        let data = try document(files: [], functions: [["filenames": [42]]])

        #expect(throws: XcodeNativeCoverageExportError.invalidEvidence(
            "LLVM coverage has invalid function filename",
        )) {
            try XcodeCoverageCompactor().compact(data, sources: [])
        }
    }

    @Test func `canonical source retains records named by a symlink alias`() throws {
        let fixture = try CompactorFixture()
        defer { fixture.remove() }
        let data = try document(
            files: [file(fixture.alias.path)],
            functions: [function(name: "aliased()", filenames: [fixture.alias.path])],
        )

        let result = try XcodeCoverageCompactor().compact(data, sources: [fixture.selected.path])
        let unit = try decodedUnit(result)

        #expect(try filenames(in: unit) == [fixture.alias.path])
        #expect(try functionNames(in: unit) == ["aliased()"])
    }

    private func document(
        files: [[String: Any]],
        functions: [[String: Any]],
        extra: [String: Any] = [:],
    ) throws -> Data {
        var unit = extra
        unit["files"] = files
        unit["functions"] = functions
        unit["totals"] = ["lines": ["count": 99]]
        return try JSONSerialization.data(withJSONObject: [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [unit],
        ])
    }

    private func file(_ filename: String) -> [String: Any] {
        ["filename": filename, "summary": ["lines": ["count": 1]]]
    }

    private func function(
        name: String,
        count: Any = 1,
        filenames: [Any],
        regions: [[Any]] = [[1, 1, 1, 2, 1, 0, 0, 0]],
        extra: [String: Any] = [:],
    ) -> [String: Any] {
        var result = extra
        result["count"] = count
        result["filenames"] = filenames
        result["name"] = name
        result["regions"] = regions
        return result
    }

    private func decodedUnit(_ data: Data) throws -> [String: Any] {
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let units = try #require(document["data"] as? [[String: Any]])
        return try #require(units.first)
    }

    private func filenames(in unit: [String: Any]) throws -> [String] {
        let files = try #require(unit["files"] as? [[String: Any]])
        return try files.map { try #require($0["filename"] as? String) }
    }

    private func functionNames(in unit: [String: Any]) throws -> [String] {
        let functions = try #require(unit["functions"] as? [[String: Any]])
        return try functions.map { try #require($0["name"] as? String) }
    }
}

private final class CompactorFixture {
    let alias: URL
    let directory: URL
    let selected: URL
    let unrelated: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        selected = directory.appendingPathComponent("Selected.swift")
        unrelated = directory.appendingPathComponent("Unrelated.swift")
        alias = directory.appendingPathComponent("SelectedAlias.swift")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("func selected() {}".utf8).write(to: selected)
        try Data("func unrelated() {}".utf8).write(to: unrelated)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: selected)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
