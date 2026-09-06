import CrapApplication
@testable import CrapCLI
import CrapCore
import Foundation
import Testing

struct BaselineTrustValidatorTests {
    @Test(arguments: ["captured", "unverified", "missing"])
    func `captured gate requires captured baseline`(verification: String) throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let report = makeReport(
            verification: verification == "missing" ? nil : verification,
            buildIdentity: "identity",
        )
        try JSONEncoder().encode(report).write(to: path)
        if verification == "captured" {
            _ = try BaselineTrustValidator().validate(path: path.path, buildIdentity: "identity")
        } else {
            #expect(throws: (any Error).self) {
                try BaselineTrustValidator().validate(path: path.path, buildIdentity: "identity")
            }
        }
    }

    @Test func `legacy captured baseline without build identity fails clearly`() throws {
        let data = try JSONEncoder().encode(makeReport(verification: "captured", buildIdentity: nil))
        let reader = BaselineFileReadingStub(data: data)

        do {
            _ = try BaselineTrustValidator(fileReader: reader)
                .validate(path: "baseline.json", buildIdentity: "identity")
            Issue.record("expected missing build identity to fail")
        } catch {
            #expect(String(describing: error).contains("captured baseline has no build identity"))
        }
    }

    @Test func `captured baseline requires the same build identity`() throws {
        let data = try JSONEncoder().encode(makeReport(verification: "captured", buildIdentity: "other"))
        let reader = BaselineFileReadingStub(data: data)

        #expect(throws: (any Error).self) {
            try BaselineTrustValidator(fileReader: reader)
                .validate(path: "baseline.json", buildIdentity: "identity")
        }
    }

    @Test func `validated baseline bytes are reused without a second read`() throws {
        let original = try JSONEncoder().encode(makeReport(verification: "captured", buildIdentity: "identity"))
        let reader = BaselineFileReadingStub(data: original)
        let baseline = try BaselineTrustValidator(fileReader: reader)
            .validate(path: "baseline.json", buildIdentity: "identity")
        reader.data = Data("changed".utf8)
        let sut = ValidatedBaselineFileReader(fileReader: reader, baseline: baseline)

        #expect(try sut.read(at: "baseline.json") == original)
        #expect(reader.paths == ["baseline.json"])
    }

    private func makeReport(verification: String?, buildIdentity: String?) -> AnalysisReport {
        AnalysisReport(
            functions: [],
            summary: ReportSummary(
                totalFunctions: 0,
                measuredFunctions: 0,
                assumedFunctions: 0,
                violations: 0,
                threshold: 30,
            ),
            verification: verification,
            buildIdentity: buildIdentity,
        )
    }
}

private final class BaselineFileReadingStub: FileReading {
    var data: Data
    private(set) var paths: [String] = []

    init(data: Data) {
        self.data = data
    }

    func read(at path: String) throws -> Data {
        paths.append(path)
        return data
    }
}
