@testable import CrapCLI
import Foundation
import Testing

struct XcodeCoverageEvidenceValidatorTests {
    @Test(arguments: DuplicateEvidence.allCases)
    func `canonical duplicate coverage paths fail closed`(_ duplicate: DuplicateEvidence) throws {
        let fixture = try ValidatorFixture()

        #expect(throws: XcodeNativeCoverageExportError
            .invalidEvidence("\(duplicate.label) repeats file \(fixture.source)"))
        {
            try XcodeCoverageEvidenceValidator().validate(
                fixture.native(duplicate: duplicate == .llvm),
                files: fixture.files(duplicate: duplicate == .report),
                archive: fixture.archive(duplicate: duplicate == .archive),
                sources: [fixture.source],
            )
        }
    }

    @Test func `nonexecutable directive subranges do not require native regions`() throws {
        let fixture = try ValidatorFixture()
        let directive = XcodeCoverageEvidenceValidator.ArchiveLine(
            executionCount: nil,
            isExecutable: false,
            line: 2,
            subranges: [XcodeCoverageEvidenceValidator.ArchiveSubrange(
                column: 1,
                executionCount: 1,
                length: 12,
            )],
        )
        var archive = fixture.archive(duplicate: false)
        archive[fixture.source]?.append(directive)

        try XcodeCoverageEvidenceValidator().validate(
            fixture.native(duplicate: false),
            files: fixture.files(duplicate: false),
            archive: archive,
            sources: [fixture.source],
        )
    }

    @Test func `executable subrange can begin at wrapped line state`() throws {
        let fixture = try ValidatorFixture()
        let files = [XcodeCoverageEvidenceValidator.File(
            coveredLines: 1,
            executableLines: 2,
            functions: [
                XcodeCoverageEvidenceValidator.Function(anchorLine: 1, coveredLines: 0, executableLines: 2),
                XcodeCoverageEvidenceValidator.Function(anchorLine: 2, coveredLines: 1, executableLines: 1),
            ],
            path: fixture.source,
        )]
        let archive = [fixture.source: [
            XcodeCoverageEvidenceValidator.ArchiveLine(
                executionCount: 0,
                isExecutable: true,
                line: 1,
                subranges: nil,
            ),
            XcodeCoverageEvidenceValidator.ArchiveLine(
                executionCount: 1,
                isExecutable: true,
                line: 2,
                subranges: [XcodeCoverageEvidenceValidator.ArchiveSubrange(
                    column: 1,
                    executionCount: 0,
                    length: 9,
                )],
            ),
        ]]

        try XcodeCoverageEvidenceValidator().validate(
            fixture.wrappedNative(),
            files: files,
            archive: archive,
            sources: [fixture.source],
        )
    }

    @Test func `subrange can end at adjacent restored subrange`() throws {
        let fixture = try ValidatorFixture()
        let files = [XcodeCoverageEvidenceValidator.File(
            coveredLines: 1,
            executableLines: 1,
            functions: [XcodeCoverageEvidenceValidator.Function(
                anchorLine: 1,
                coveredLines: 1,
                executableLines: 1,
            )],
            path: fixture.source,
        )]
        let archive = [fixture.source: [XcodeCoverageEvidenceValidator.ArchiveLine(
            executionCount: 10,
            isExecutable: true,
            line: 1,
            subranges: [
                XcodeCoverageEvidenceValidator.ArchiveSubrange(column: 45, executionCount: 1, length: 10),
                XcodeCoverageEvidenceValidator.ArchiveSubrange(column: 55, executionCount: 9, length: 0),
            ],
        )]]

        try XcodeCoverageEvidenceValidator().validate(
            fixture.adjacentSubrangesNative(),
            files: files,
            archive: archive,
            sources: [fixture.source],
        )
    }

    @Test func `native machine functions sharing source span merge region coverage`() throws {
        let fixture = try ValidatorFixture()

        try XcodeCoverageEvidenceValidator().validate(
            fixture.nativeWithAliasedFunction(),
            files: fixture.files(duplicate: false),
            archive: fixture.archive(duplicate: false),
            sources: [fixture.source],
        )
    }

    @Test func `subrange can end at native region exit`() throws {
        let fixture = try ValidatorFixture()
        let archive = [fixture.source: [XcodeCoverageEvidenceValidator.ArchiveLine(
            executionCount: 16,
            isExecutable: true,
            line: 1,
            subranges: [XcodeCoverageEvidenceValidator.ArchiveSubrange(
                column: 119,
                executionCount: 0,
                length: 4,
            )],
        )]]

        try XcodeCoverageEvidenceValidator().validate(
            fixture.regionExitNative(),
            files: fixture.files(duplicate: false),
            archive: archive,
            sources: [fixture.source],
        )
    }

    @Test func `function evidence for an unreported authored source fails closed`() throws {
        let fixture = try ValidatorFixture()

        #expect(throws: XcodeNativeCoverageExportError.invalidEvidence(
            "function coverage has no file evidence for \(fixture.missingSource)",
        )) {
            try XcodeCoverageEvidenceValidator().validate(
                fixture.nativeWithUnreportedSourceFunction(),
                files: fixture.files(duplicate: false),
                archive: fixture.archive(duplicate: false),
                sources: [fixture.source, fixture.missingSource],
            )
        }
    }
}

enum DuplicateEvidence: CaseIterable {
    case archive
    case llvm
    case report

    var label: String {
        switch self {
        case .archive: "xccov archive"
        case .llvm: "LLVM"
        case .report: "xccov report"
        }
    }
}

private final class ValidatorFixture {
    let alias: String
    let directory: URL
    let missingSource: String
    let source: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-crap-validator-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        source = directory.appendingPathComponent("Subject.swift").path
        missingSource = directory.appendingPathComponent("Missing.swift").path
        alias = directory.appendingPathComponent("Alias.swift").path
        FileManager.default.createFile(atPath: source, contents: Data("func subject() {}\n".utf8))
        FileManager.default.createFile(atPath: missingSource, contents: Data("func missing() {}\n".utf8))
        try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: source)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func archive(duplicate: Bool) -> [String: [XcodeCoverageEvidenceValidator.ArchiveLine]] {
        let lines = [XcodeCoverageEvidenceValidator.ArchiveLine(
            executionCount: 1,
            isExecutable: true,
            line: 1,
            subranges: nil,
        )]
        return duplicate ? [source: lines, alias: lines] : [source: lines]
    }

    func adjacentSubrangesNative() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [[
                "files": [[
                    "filename": source,
                    "segments": [
                        [1, 1, 10, true, true, false],
                        [1, 45, 1, true, true, false],
                        [1, 55, 9, true, true, false],
                        [2, 1, 0, false, false, false],
                    ],
                    "summary": ["lines": ["count": 1, "covered": 1]],
                ]],
                "functions": [[
                    "count": 10,
                    "filenames": [source],
                    "name": "subject",
                    "regions": [[1, 1, 1, 60, 10, 0, 0, 0]],
                ]],
            ]],
        ])
    }

    func files(duplicate: Bool) -> [XcodeCoverageEvidenceValidator.File] {
        let paths = duplicate ? [source, alias] : [source]
        return paths.map {
            XcodeCoverageEvidenceValidator.File(
                coveredLines: 1,
                executableLines: 1,
                functions: [XcodeCoverageEvidenceValidator.Function(
                    anchorLine: 1,
                    coveredLines: 1,
                    executableLines: 1,
                )],
                path: $0,
            )
        }
    }

    func native(duplicate: Bool) throws -> Data {
        let paths = duplicate ? [source, alias] : [source]
        return try JSONSerialization.data(withJSONObject: [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [[
                "files": paths.map { path in
                    [
                        "filename": path,
                        "segments": [
                            [1, 1, 1, true, true, false],
                            [2, 1, 0, false, false, false],
                        ],
                        "summary": ["lines": ["count": 1, "covered": 1]],
                    ]
                },
                "functions": [[
                    "count": 1,
                    "filenames": [source],
                    "name": "subject",
                    "regions": [[1, 1, 1, 18, 1, 0, 0, 0]],
                ]],
            ]],
        ])
    }

    func nativeWithAliasedFunction() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [[
                "files": [[
                    "filename": source,
                    "segments": [
                        [1, 1, 1, true, true, false],
                        [2, 1, 0, false, false, false],
                    ],
                    "summary": ["lines": ["count": 1, "covered": 1]],
                ]],
                "functions": [
                    [
                        "count": 0,
                        "filenames": [source],
                        "name": "source",
                        "regions": [[1, 1, 1, 18, 0, 0, 0, 0]],
                    ],
                    [
                        "count": 1,
                        "filenames": [source],
                        "name": "thunk",
                        "regions": [
                            [1, 1, 1, 18, 0, 0, 0, 0],
                            [1, 5, 1, 10, 1, 0, 0, 0],
                        ],
                    ],
                ],
            ]],
        ])
    }

    func nativeWithUnreportedSourceFunction() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [[
                "files": [[
                    "filename": source,
                    "segments": [
                        [1, 1, 1, true, true, false],
                        [2, 1, 0, false, false, false],
                    ],
                    "summary": ["lines": ["count": 1, "covered": 1]],
                ]],
                "functions": [
                    [
                        "count": 1,
                        "filenames": [source],
                        "name": "subject",
                        "regions": [[1, 1, 1, 18, 1, 0, 0, 0]],
                    ],
                    [
                        "count": 1,
                        "filenames": [source, missingSource],
                        "name": "mixed",
                        "regions": [
                            [1, 1, 1, 18, 1, 0, 0, 0],
                            [1, 1, 1, 18, 1, 1, 0, 0],
                        ],
                    ],
                ],
            ]],
        ])
    }

    func regionExitNative() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [[
                "files": [[
                    "filename": source,
                    "segments": [
                        [1, 1, 16, true, true, false],
                        [1, 119, 0, true, true, false],
                        [1, 123, 0, false, false, false],
                    ],
                    "summary": ["lines": ["count": 1, "covered": 1]],
                ]],
                "functions": [[
                    "count": 16,
                    "filenames": [source],
                    "name": "subject",
                    "regions": [[1, 1, 1, 123, 16, 0, 0, 0]],
                ]],
            ]],
        ])
    }

    func wrappedNative() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [[
                "files": [[
                    "filename": source,
                    "segments": [
                        [1, 1, 0, true, true, false],
                        [2, 10, 1, true, false, false],
                        [2, 17, 1, true, true, false],
                        [2, 20, 0, false, false, false],
                    ],
                    "summary": ["lines": ["count": 2, "covered": 1]],
                ]],
                "functions": [
                    [
                        "count": 0,
                        "filenames": [source],
                        "name": "zero",
                        "regions": [[1, 1, 2, 10, 0, 0, 0, 0]],
                    ],
                    [
                        "count": 1,
                        "filenames": [source],
                        "name": "covered",
                        "regions": [[2, 10, 2, 20, 1, 0, 0, 0]],
                    ],
                ],
            ]],
        ])
    }
}
