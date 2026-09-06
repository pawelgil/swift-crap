import CrapApplication
@testable import CrapCLI
import CrapCore
import Testing

struct CLIArgumentParserTests {
    @Test func `analyze parses repeated coverage and options`() throws {
        let sut = createSUT()

        let action = try sut.parse([
            "analyze", "--file", "Source.swift", "--coverage", "one.json",
            "--coverage", "two.json", "--format", "json", "--missing", "zero",
            "--threshold", "12.5", "--root", "/project",
        ])

        guard case let .analyze(request, format) = action else {
            Issue.record("expected analyze action")
            return
        }
        #expect(request.selection == SourceSelectionRequest(scope: .file("Source.swift"), rootOverride: "/project"))
        #expect(request.coverageFiles == ["one.json", "two.json"])
        #expect(request.missing == .zero)
        #expect(request.threshold == 12.5)
        #expect(format == .json)
    }

    @Test func `analyze requires exactly one selector`() {
        let sut = createSUT()

        #expect(throws: CLIError.selection("exactly one source selector is required")) {
            try sut.parse([
                "analyze", "--file", "Source.swift", "--project", "/project",
                "--coverage", "coverage.json",
            ])
        }
    }

    @Test func `invalid threshold is rejected`() {
        let sut = createSUT()

        #expect(throws: CLIError.invalidValue(option: "--threshold", value: "nan")) {
            try sut.parse([
                "analyze", "--file", "Source.swift", "--coverage", "coverage.json",
                "--threshold", "nan",
            ])
        }
    }

    @Test func `help does not require analysis options`() throws {
        let sut = createSUT()

        let action = try sut.parse(["--help"])

        guard case .help = action else {
            Issue.record("expected help action")
            return
        }
    }

    private func createSUT() -> CLIArgumentParser {
        CLIArgumentParser()
    }
}
